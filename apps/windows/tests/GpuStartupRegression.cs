using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using NCF;
class GpuStartupRegression {
 static readonly BindingFlags Flags=BindingFlags.Instance|BindingFlags.NonPublic;static int count;
 static object Field(MainWindow w,string name){return typeof(MainWindow).GetField(name,Flags).GetValue(w);}
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
 static void Pump(){var f=new DispatcherFrame();var t=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(20)};t.Tick+=delegate{t.Stop();f.Continue=false;};t.Start();Dispatcher.PushFrame(f);}
 static void Until(Func<bool> condition){var s=System.Diagnostics.Stopwatch.StartNew();while(!condition()&&s.ElapsedMilliseconds<6000)Pump();Check(condition(),"Bounded UI completion");}
 static void Png(string path){var source=BitmapSource.Create(17,13,96,96,PixelFormats.Bgr24,null,new byte[17*13*3],17*3);var e=new PngBitmapEncoder();e.Frames.Add(BitmapFrame.Create(source));using(var f=File.Create(path))e.Save(f);}
 static Task Call(MainWindow w,string name,params object[] args){return (Task)typeof(MainWindow).GetMethod(name,Flags).Invoke(w,args);}
 [STAThread]static int Main(string[] args){MainWindow w=null,closed=null;try{Directory.CreateDirectory(args[0]);TemporarySession.RegressionRoot=Path.Combine(args[0],"sessions");var a=Path.Combine(args[0],"A.png");var b=Path.Combine(args[0],"B.png");Png(a);Png(b);var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());var pending=new TaskCompletionSource<bool>();w=new MainWindow(a);w.ErrorOverride=message=>{throw new Exception(message);};w.GpuCapabilityOverride=()=>pending.Task;w.Show();Until(()=>Convert.ToString(Field(w,"sourcePath"))==a&&!(bool)Field(w,"loading"));Check(!pending.Task.IsCompleted,"Initial image opens without waiting for GPU probe");Check((bool)Field(w,"gpuChecking"),"Probe remains pending while image is available");
 var enhance=Call(w,"Enhance");Check(enhance.IsCompleted&&!w.TestBusy&&!(bool)Field(w,"preparingModels"),"Shared Enhance entry used by button and Ctrl+U is gated during GPU probe");enhance.GetAwaiter().GetResult();
 var open=Call(w,"OpenPath",b);Until(()=>open.IsCompleted);open.GetAwaiter().GetResult();Check(Convert.ToString(Field(w,"sourcePath"))==b,"User can open B while GPU probe is pending");pending.SetResult(true);Until(()=>!(bool)Field(w,"gpuChecking"));Check(Convert.ToString(Field(w,"sourcePath"))==b,"Completed probe does not restore deferred initial A");
 var closing=new TaskCompletionSource<bool>();closed=new MainWindow(null);closed.GpuCapabilityOverride=()=>closing.Task;closed.Show();Pump();closed.ForceTestClose();Check((bool)Field(closed,"windowClosed")&&(bool)Field(closed,"gpuProbeStopped"),"Closed window marks probe stopped");closing.SetResult(true);Pump();Check(!(bool)Field(closed,"gpuAvailable"),"Late probe completion cannot revive closed window");Check(File.Exists(a)&&File.Exists(b),"Input files retained");Console.WriteLine(count+" assertions; controlled probe completion and WPF entrypoints; no GPU/network/native keyboard input");return 0;}catch(Exception error){Console.Error.WriteLine(error);return 1;}finally{if(w!=null)w.ForceTestClose();if(closed!=null&&!(bool)Field(closed,"windowClosed"))closed.ForceTestClose();}}
}