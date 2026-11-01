using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using NCF;

public static class CloseRegression {
    static int failures;static readonly List<Exception> errors=new List<Exception>();
    static void Pump(int milliseconds) {var frame=new DispatcherFrame();var timer=new DispatcherTimer {Interval=TimeSpan.FromMilliseconds(milliseconds)};timer.Tick+=delegate {timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);}
    static void Assert(bool condition,string message){if(!condition)throw new Exception(message);}
    [STAThread] public static int Main(string[] args) {try{return Run(args);}catch(Exception e){Console.WriteLine(e.ToString());return 1;}}
    static int Run(string[] args) {
        var app=new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};app.DispatcherUnhandledException+=delegate(object sender,DispatcherUnhandledExceptionEventArgs e){errors.Add(e.Exception);e.Handled=true;};
        string root=args[0];Directory.CreateDirectory(root);var results=new List<string>();
        foreach(string kind in new string[]{"discard","cancel","save","save-cancelled","save-failed","repeat-close","busy-then-cancel"}) {
            MainWindow window=null;
            try {
                string original=Path.Combine(root,kind+"-source.png"),result=Path.Combine(root,kind+"-result.png"),saved=Path.Combine(root,kind+"-saved.png");
                File.WriteAllBytes(original,new byte[]{1,2,3});File.WriteAllBytes(result,new byte[]{4,5,6});
                window=new MainWindow(null);int choices=0,closed=0;
                window.DecisionOverride=delegate(string title,string text,string[] labels){choices++;if(title=="Close while processing?")return 0;if(kind=="cancel"||kind=="busy-then-cancel")return 2;if(kind.StartsWith("save"))return 0;return 1;};
                window.SaveOverride=async delegate(bool saveAs) {await Task.Delay(10);if(kind=="save"){MainWindow.Publish(original,result,saved,false);return true;}return false;};
                window.Closed+=delegate {closed++;};window.Show();Pump(15);window.SetTestState(original,result,kind=="busy-then-cancel");
                window.Close();
                if(kind=="repeat-close"){window.Close();window.Close();}
                Pump(80);
                Assert(errors.Count==0,"Dispatcher exception during "+kind);
                Assert(File.ReadAllBytes(original)[0]==1,"Original changed");
                if(kind=="cancel"||kind=="save-cancelled"||kind=="save-failed")Assert(closed==0&&window.IsVisible&&window.TestDirty,"Window/result lost on cancelled/failed close");
                else if(kind=="busy-then-cancel") {
                    Assert(closed==0&&window.TestBusy&&window.TestCancelRequested,"Busy close did not wait");
                    window.CompleteTestWork().Wait();Pump(60);
                    Assert(closed==0&&window.IsVisible&&!window.TestBusy&&window.TestDirty,"Cancel of later unsaved prompt lost state");
                } else {Assert(closed==1,"Did not close exactly once");if(kind=="save")Assert(File.Exists(saved)&&File.ReadAllBytes(saved)[0]==4,"Save did not finish before close");}
                if(kind=="repeat-close")Assert(choices==1,"Repeated close created duplicate prompts");
                results.Add(kind+": PASS");
            }catch(Exception error){failures++;results.Add(kind+": FAIL "+error.Message);}
            finally{if(window!=null&&window.IsVisible)window.ForceTestClose();Pump(15);}
        }
        Assert(errors.Count==0,"Unhandled WPF Dispatcher exception");
        File.WriteAllLines(Path.Combine(root,"close-regression.txt"),results);foreach(string line in results)Console.WriteLine(line);
        Console.WriteLine("WPF component lifecycle regression, scripted decisions; not an end-to-end user GUI verification.");
        app.Shutdown();return failures==0?0:1;
    }
}
