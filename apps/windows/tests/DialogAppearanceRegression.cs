using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using NCF;
class DialogAppearanceRegression {
 static int count;static Exception failure;static BindingFlags Flags=BindingFlags.NonPublic|BindingFlags.Instance;static string root;
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
 static double L(Brush brush){var c=((SolidColorBrush)brush).Color;Func<byte,double> channel=x=>{double v=x/255.0;return v<=.04045?v/12.92:Math.Pow((v+.055)/1.055,2.4);};return .2126*channel(c.R)+.7152*channel(c.G)+.0722*channel(c.B);}
 static double Contrast(Brush a,Brush b){double x=L(a),y=L(b);return (Math.Max(x,y)+.05)/(Math.Min(x,y)+.05);}
 static void Walk(DependencyObject d,Action<DependencyObject> action){action(d);for(int i=0;i<VisualTreeHelper.GetChildrenCount(d);i++)Walk(VisualTreeHelper.GetChild(d,i),action);}
 static void Inspect(Window dialog,string label){dialog.UpdateLayout();Check(Contrast(dialog.Foreground,dialog.Background)>=4.5,label+" window text contrast");int text=0,buttons=0,boxes=0;Walk(dialog,d=>{var t=d as TextBlock;if(t!=null&&!String.IsNullOrEmpty(t.Text)){Check(Contrast(t.Foreground,dialog.Background)>=4.5,label+" text readable");text++;}var b=d as Button;if(b!=null){Check(Contrast(b.Foreground,b.Background)>=4.5,label+" button readable");buttons++;}var box=d as TextBox;if(box!=null){Check(Contrast(box.Foreground,box.Background)>=4.5,label+" text field readable");boxes++;}});Check(text>0&&buttons>0,label+" actual controls inspected");}
 static void Schedule(string title,string label,bool render){var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(100)};timer.Tick+=delegate{var dialog=Application.Current.Windows.Cast<Window>().FirstOrDefault(w=>w.Title==title);if(dialog==null)return;timer.Stop();try{Inspect(dialog,label);if(render){var image=new RenderTargetBitmap((int)Math.Ceiling(dialog.ActualWidth),(int)Math.Ceiling(dialog.ActualHeight),96,96,PixelFormats.Pbgra32);image.Render(dialog);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using(var f=File.Create(Path.Combine(root,label+"-component.png")))png.Save(f);}}catch(Exception e){failure=e;}finally{dialog.Close();}};timer.Start();}
 [STAThread]static void Main(string[] args){root=args[0];TemporarySession.RegressionRoot=Path.Combine(root,"sessions");var app=new Application();System.Threading.SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());var owner=new MainWindow(null);owner.Show();for(int i=0;i<3;i++){typeof(MainWindow).GetMethod("ApplyAppearance",Flags).Invoke(owner,new object[]{i});string label=new[]{"Soft","Fluent","Studio"}[i];Schedule("Confirmation contrast",label+"-confirmation",i==2);var answer=typeof(MainWindow).GetMethod("Choice",Flags).Invoke(owner,new object[]{"Confirmation contrast","Keep or discard the unsaved result?",new[]{"Save","Discard Result","Cancel"}});if(failure!=null)throw failure;Check((int)answer==2,label+" closing confirmation remains Cancel");Schedule("Rename contrast",label+"-rename",i==2);var name=typeof(MainWindow).GetMethod("Input",Flags).Invoke(owner,new object[]{"Rename contrast","Sample.png"});if(failure!=null)throw failure;Check(name==null,label+" closing rename remains Cancel");var models=new ModelsWindow(owner,false,new ModelSpec[0]);models.Show();Inspect(models,label+" models");models.Close();}owner.ForceTestClose();Console.WriteLine(count+" assertions; real WPF modal dialogs with controlled close, no native mouse input or downloads");}
}