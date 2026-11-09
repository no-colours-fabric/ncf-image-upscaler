using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using NCF;
class MaximizeRegression {
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr hwnd,out MaximizedBounds.Rect rect);
 static int count;static void Check(bool ok,string name){if(!ok)throw new Exception(name);Console.WriteLine("PASS "+name);count++;}
 static void Pump(){var f=new DispatcherFrame();var t=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(160)};t.Tick+=delegate{t.Stop();f.Continue=false;};t.Start();Dispatcher.PushFrame(f);}
 static MaximizedBounds.Rect R(int l,int t,int r,int b){return new MaximizedBounds.Rect{Left=l,Top=t,Right=r,Bottom=b};}
 [STAThread]static void Main(string[] args){
 var m=R(0,0,1920,1080);var def=new MaximizedBounds.MinMaxInfo{MinTrackSize=new MaximizedBounds.Point{X=1056,Y=579}};
 foreach(var w in new[]{R(0,0,1920,1040),R(0,40,1920,1080),R(40,0,1920,1080),R(0,0,1880,1080),m}){var r=MaximizedBounds.Calculate(def,m,w);Check(r.MaxPosition.X==w.Left&&r.MaxPosition.Y==w.Top&&r.MaxSize.X==w.Right-w.Left&&r.MaxSize.Y==w.Bottom-w.Top,"Work area: bottom/top/left/right/auto-hide geometry "+count);Check(r.MinTrackSize.X==1056&&r.MinTrackSize.Y==579,"Minimum resize constraints preserved");}
 var negative=MaximizedBounds.Calculate(def,R(-2560,-1440,0,0),R(-2512,-1440,0,0));Check(negative.MaxPosition.X==48&&negative.MaxPosition.Y==0&&negative.MaxSize.X==2512&&negative.MaxSize.Y==1440,"Negative monitor coordinates and physical-pixel dimensions");
 TemporarySession.RegressionRoot=Path.Combine(args[0],"sessions");var app=new Application();System.Threading.SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());MaximizedBounds.MonitorInfo primary;Check(MaximizedBounds.TryGetMonitor(IntPtr.Zero,out primary),"Primary work area for bounded test placement");var workDip=SystemParameters.WorkArea;var win=new MainWindow(null){MinWidth=Math.Min(600,workDip.Width*.4),MinHeight=Math.Min(400,workDip.Height*.4),Width=Math.Min(1150,workDip.Width*.75),Height=Math.Min(700,workDip.Height*.75),WindowStartupLocation=WindowStartupLocation.Manual,Left=workDip.Left+workDip.Width*.125,Top=workDip.Top+workDip.Height*.125};win.Show();Pump();var handle=new WindowInteropHelper(win).Handle;MaximizedBounds.MonitorInfo info;Check(MaximizedBounds.TryGetMonitor(handle,out info),"Actual monitor/work-area query");MaximizedBounds.Rect original;GetWindowRect(handle,out original);
 for(int i=0;i<2;i++){win.WindowState=WindowState.Maximized;Pump();MaximizedBounds.Rect rect;GetWindowRect(handle,out rect);Console.WriteLine("TRACE work="+info.Work.Left+","+info.Work.Top+","+info.Work.Right+","+info.Work.Bottom+" maximized="+rect.Left+","+rect.Top+","+rect.Right+","+rect.Bottom);Check(rect.Left==info.Work.Left&&rect.Top==info.Work.Top&&rect.Right==info.Work.Right&&rect.Bottom==info.Work.Bottom,"Actual HWND maximization fits taskbar-free work area "+i);win.WindowState=WindowState.Normal;Pump();GetWindowRect(handle,out rect);Console.WriteLine("TRACE original="+original.Left+","+original.Top+","+original.Right+","+original.Bottom+" restored="+rect.Left+","+rect.Top+","+rect.Right+","+rect.Bottom);Check(rect.Left==original.Left&&rect.Top==original.Top&&rect.Right==original.Right&&rect.Bottom==original.Bottom,"Restore returns to previous bounds "+i);}
 win.ForceTestClose();Console.WriteLine(count+" PASS; synthetic monitor layouts plus actual controlled WPF maximize/restore. Not native mouse input; other taskbar positions not changed on host.");
 }
}