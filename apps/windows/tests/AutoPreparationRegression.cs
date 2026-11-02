using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using NCF;

public static class AutoPreparationRegression {
 static readonly List<string> report=new List<string>();static string root,artifacts;static int workers,transfers,visible;
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);report.Add("PASS "+name);Console.WriteLine("PASS "+name);}
 static object Field(object o,string name){return o.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(o);}
 static void Pump(int ms){var frame=new DispatcherFrame();var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(ms)};timer.Tick+=delegate{timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);}
 static void Until(Func<bool> condition){var watch=System.Diagnostics.Stopwatch.StartNew();while(!condition()&&watch.ElapsedMilliseconds<10000)Pump(10);if(!condition())throw new Exception("Bounded component wait expired");}
 static void Wait(Task task){Until(()=>task.IsCompleted);task.GetAwaiter().GetResult();Pump(20);}
 static Task Call(MainWindow w,string method,params object[] args){return (Task)w.GetType().GetMethod(method,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(w,args);}
 static string Sha(string path){using(var hash=SHA256.Create())using(var file=File.OpenRead(path))return BitConverter.ToString(hash.ComputeHash(file)).Replace("-","").ToLowerInvariant();}
 static void Png(string path,byte color){var source=BitmapSource.Create(24,17,96,96,PixelFormats.Bgr24,null,Enumerable.Repeat(color,24*17*3).ToArray(),24*3);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(source));using(var file=new FileStream(path,FileMode.CreateNew))encoder.Save(file);}
 static void Setup(){
  artifacts=Path.Combine(root,"controlled-artifacts");Directory.CreateDirectory(artifacts);ModelStore.Root=Path.Combine(root,"controlled-cache");Directory.CreateDirectory(ModelStore.Root);
  var specs=new List<Dictionary<string,object>>();foreach(string id in new[]{"photo2","photo4","illustration","fast"}){string path=Path.Combine(artifacts,id+".bytes");File.WriteAllText(path,"NOT ONNX: controlled preparation bytes for "+id);specs.Add(new Dictionary<string,object>{{"id",id},{"name",id},{"repository","controlled/no-network"},{"revision",new string('0',40)},{"file","model.onnx"},{"bytes",new FileInfo(path).Length},{"sha256",Sha(path)},{"native_scale",id=="photo2"?2:4}});}
  Directory.CreateDirectory(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"resources"));File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"resources/models.json"),new JavaScriptSerializer().Serialize(specs));
 }
 static MainWindow Window(string name,bool image,Action<MainWindow> beforeShow=null){
  var w=new MainWindow(null);w.ErrorOverride=e=>{throw new Exception(e);};w.DecisionOverride=(t,m,labels)=>t=="Unsaved enhancement"?2:0;w.WorkerArgumentsOverride=args=>{if(!ModelStore.Verified(ModelStore.Select("fast",1)))throw new Exception("Worker launched before verified required model");Interlocked.Increment(ref workers);};if(beforeShow!=null)beforeShow(w);w.Show();Pump(30);
  if(image){string directory=Path.Combine(root,name);Directory.CreateDirectory(directory);string source=Path.Combine(directory,"source.png"),result=Path.Combine(directory,"previous.png");Png(source,90);Png(result,170);Wait(Call(w,"OpenPath",source));((ComboBox)Field(w,"model")).SelectedIndex=2;((ComboBox)Field(w,"scale")).SelectedIndex=0;w.SetTestState(source,result,false);var doc=(ImageDocument)Field(w,"document");doc.Result=result;((ImageCanvas)Field(w,"canvas")).SetResult(MainWindow.LoadBitmap(result));}
  return w;
 }
 static void Configure(MainWindow w,string kind){w.PreparationWindowOverride=dialog=>{
  dialog.Loaded+=delegate{if(dialog.IsVisible)visible++;if(kind=="cancel")dialog.CancelAndClose();if(kind=="preset")((ComboBox)Field(w,"model")).SelectedIndex=1;if(kind=="revision")File.SetLastWriteTimeUtc((string)Field(w,"sourcePath"),DateTime.UtcNow.AddSeconds(3));if(kind=="close")w.Close();};
  dialog.DownloadOverride=(spec,stop,progress)=>{
   Interlocked.Increment(ref transfers);stop.ThrowIfCancellationRequested();
   if(kind=="error")throw new IOException("Controlled transfer error");
   if(kind=="cancel"||kind=="close"){stop.WaitHandle.WaitOne(5000);stop.ThrowIfCancellationRequested();throw new Exception("Cancellation was not observed");}
   File.Copy(Path.Combine(artifacts,spec.id+".bytes"),Path.Combine(ModelStore.Root,spec.LocalName),true);progress(spec.bytes);
  };
  dialog.PreparationFinishedOverride=completed=>{if(!completed.Ready&&kind=="error")completed.Close();};
 };}
 static void MissingFast(){var spec=ModelStore.Select("fast",1);string path=Path.Combine(ModelStore.Root,spec.LocalName);if(File.Exists(path))File.Delete(path);}
 [STAThread] public static int Main(string[] args){root=Path.GetFullPath(args[0]);Directory.CreateDirectory(root);TemporarySession.RegressionRoot=Path.Combine(root,"sessions");var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());MainWindow current=null;
 try{Setup();
  current=Window("startup",false,w=>{Configure(w,"success");w.PrepareModelsWhenLoaded=true;});Until(()=>visible==1&&!(bool)Field(current,"preparingModels"));Check(visible==1&&transfers==4&&workers==0,"Empty cache opens visible automatic preparation from Loaded before any worker");Check(ModelStore.Read().All(ModelStore.Verified),"Automatic preparation requires final real SHA verification (synthetic fixture bytes)");int count=transfers;Wait(current.PrepareAtStartup());Check(transfers==count&&visible==1,"Repeated startup notification does not reopen or retry preparation");current.ForceTestClose();current=null;
  int shown=visible;current=Window("verified",false,w=>{Configure(w,"success");w.PrepareModelsWhenLoaded=true;});Until(()=>!(bool)Field(current,"preparingModels"));Check(transfers==count&&visible==shown,"Verified cache skips preparation and all transfer calls");current.ForceTestClose();current=null;
  MissingFast();current=Window("required",true);Configure(current,"success");string original=(string)Field(current,"sourcePath"),previous=(string)Field(current,"resultPath");string originalHash=Sha(original),previousHash=Sha(previous);Wait(Call(current,"Enhance"));Check(workers==1&&transfers==count+1,"Missing required artifact prepares only that model before worker hook");Check(Sha(original)==originalHash&&Sha(previous)==previousHash&&current.TestDirty,"Preparation and simulated worker cancellation preserve source and previous result");current.ForceTestClose();current=null;
  var fast=ModelStore.Select("fast",1);string corrupt=Path.Combine(ModelStore.Root,fast.LocalName);var broken=File.ReadAllBytes(corrupt);broken[0]^=1;File.WriteAllBytes(corrupt,broken);Check(ModelStore.Present(fast)&&!ModelStore.Verified(fast),"Same-size corrupt cache is not verified ready");current=Window("corrupt",true);Configure(current,"success");int beforeRepair=workers;Wait(Call(current,"Enhance"));Check(workers==beforeRepair+1&&ModelStore.Verified(fast),"Corrupt required model is repaired and verified before worker hook");current.ForceTestClose();current=null;
  foreach(string kind in new[]{"cancel","error","preset","revision","close"}){
   MissingFast();current=Window(kind,true);Configure(current,kind);original=(string)Field(current,"sourcePath");previous=(string)Field(current,"resultPath");originalHash=Sha(original);previousHash=Sha(previous);int beforeWorkers=workers;Wait(Call(current,"Enhance"));if(kind=="close")Until(()=>!(bool)Field(current,"closeWhenDone"));count=transfers;Pump(100);
   Check(workers==beforeWorkers&&transfers==count,kind+" blocks worker and causes no hidden transfer retry");
   Check(current.IsVisible&&current.TestDirty&&Sha(original)==originalHash&&Sha(previous)==previousHash,kind+" keeps current window, original and prior unsaved result");current.ForceTestClose();current=null;
  }
  report.Add("NOTE controlled WPF visible-modal/source lifecycle checks with synthetic model bytes and controlled transport/worker hook; no network, real ONNX inference or native desktop input. Production downloader integrity/HTTPS has separate evidence.");File.WriteAllLines(Path.Combine(root,"auto-preparation-report.txt"),report);app.Shutdown();return 0;
 }catch(Exception error){report.Add("FAIL "+error);File.WriteAllLines(Path.Combine(root,"auto-preparation-report.txt"),report);Console.Error.WriteLine(error);if(current!=null)current.ForceTestClose();app.Shutdown();return 1;}}
}
