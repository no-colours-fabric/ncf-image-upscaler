using System;
using System.IO;
using System.Net;
using System.Linq;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;

namespace NCF {
public sealed class ModelSpec {
 public string id, name, repository, revision, file, sha256, license;
 public long bytes;
 public int native_scale;
 public string Url {get{return "https://huggingface.co/"+repository+"/resolve/"+revision+"/"+file;}}
 public string LocalName {get{return id+"-"+sha256+".onnx";}}
}
public static class ModelStore {
#if MODELS_REGRESSION
 public static string Root;
#else
 public static readonly string Root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NCF Image Upscaler","models");
#endif
 public static ModelSpec[] Read(){return new JavaScriptSerializer().Deserialize<ModelSpec[]>(File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"resources","models.json")));}
 public static ModelSpec Select(string preset,int scale){return Read().Single(x=>x.id==(preset=="photo"?(scale==4?"photo4":"photo2"):preset));}
 public static bool Present(ModelSpec model){var path=Path.Combine(Root,model.LocalName);return File.Exists(path)&&new FileInfo(path).Length==model.bytes;}
 public static bool Verified(ModelSpec model){try{var path=Path.Combine(Root,model.LocalName);if(!Present(model))return false;using(var hash=SHA256.Create())using(var file=File.OpenRead(path))return BitConverter.ToString(hash.ComputeHash(file)).Replace("-","").ToLowerInvariant()==model.sha256;}catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}}
 // Only the visible preparation window calls this method. Inference never does.
 public static void Download(ModelSpec model,CancellationToken stop,Action<long> progress){
  Directory.CreateDirectory(Root);
  using(var lease=new FileStream(Path.Combine(Root,"download.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
   stop.ThrowIfCancellationRequested();if(Verified(model)){progress(model.bytes);return;}
   string temporary=Path.Combine(Root,"download-"+Guid.NewGuid().ToString("N")+".partial");
   try{
    ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
    var request=(HttpWebRequest)WebRequest.Create(model.Url);request.Timeout=30000;request.ReadWriteTimeout=30000;request.UserAgent="NCF-Image-Upscaler-Windows/0.1.0-preview.1";
    using(stop.Register(request.Abort))using(var response=(HttpWebResponse)request.GetResponse())using(var input=response.GetResponseStream())using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))using(var hash=SHA256.Create()){
     if(response.ResponseUri.Scheme!="https")throw new IOException("An insecure download redirect was refused.");
     long received=0;var buffer=new byte[131072];int count;
     while((count=input.Read(buffer,0,buffer.Length))>0){stop.ThrowIfCancellationRequested();received+=count;if(received>model.bytes)throw new IOException("Model size does not match the pinned manifest.");output.Write(buffer,0,count);hash.TransformBlock(buffer,0,count,buffer,0);progress(received);}
     hash.TransformFinalBlock(new byte[0],0,0);if(received!=model.bytes||BitConverter.ToString(hash.Hash).Replace("-","").ToLowerInvariant()!=model.sha256)throw new IOException("Model integrity check failed. Please retry the download.");output.Flush(true);
    }
    stop.ThrowIfCancellationRequested();string target=Path.Combine(Root,model.LocalName);
    if(File.Exists(target))File.Replace(temporary,target,null);else File.Move(temporary,target);
   }catch{stop.ThrowIfCancellationRequested();throw;}finally{if(File.Exists(temporary))File.Delete(temporary);}
  }
 }
}
public sealed class ModelsWindow : Window {
 readonly ModelSpec[] models;readonly bool automatic;readonly TextBlock text=new TextBlock{TextWrapping=TextWrapping.Wrap};readonly ProgressBar progress=new ProgressBar{Height=8,Margin=new Thickness(0,14,0,14)};
 readonly Button download=new Button{Content="Download / Repair Models",Padding=new Thickness(12,6,12,6)},cancel=new Button{Content="Cancel Download",Padding=new Thickness(12,6,12,6),Margin=new Thickness(10,0,0,0),IsEnabled=false};
 CancellationTokenSource stop;bool running,closeAfter,automaticStarted;
 public bool Ready {get;private set;}
 public string FailureMessage {get;private set;}
#if AUTO_PREPARATION_REGRESSION
 public Action<ModelSpec,CancellationToken,Action<long>> DownloadOverride;
 public Action<ModelsWindow> PreparationFinishedOverride;
#endif
 public ModelsWindow(Window owner,bool autoStart=false,ModelSpec[] required=null){models=required??ModelStore.Read();automatic=autoStart;Owner=owner;Title="Models — NCF Image Upscaler";Width=580;Height=440;ResizeMode=ResizeMode.NoResize;WindowStartupLocation=WindowStartupLocation.CenterOwner;
  var panel=new StackPanel{Margin=new Thickness(24)};Content=panel;
  panel.Children.Add(new TextBlock{Text="Prepare offline image enhancement",FontSize=20,Margin=new Thickness(0,0,0,12)});
  panel.Children.Add(new TextBlock{Text="Missing or damaged models are prepared automatically from Hugging Face before processing. You can cancel this preparation. No account is required; image inference stays local.",TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,12)});
  panel.Children.Add(text);panel.Children.Add(progress);var buttons=new StackPanel{Orientation=Orientation.Horizontal};buttons.Children.Add(download);buttons.Children.Add(cancel);panel.Children.Add(buttons);
  panel.Children.Add(new TextBlock{Text="Model folder: "+ModelStore.Root,TextWrapping=TextWrapping.Wrap,FontSize=11,Margin=new Thickness(0,16,0,0)});
  download.Click+=async delegate{await Prepare();};cancel.Click+=delegate{RequestCancel(automatic);};
  PreviewKeyDown+=delegate(object sender,System.Windows.Input.KeyEventArgs e){if(e.Key==System.Windows.Input.Key.Escape){e.Handled=true;CancelAndClose();}};
  Closing+=delegate(object sender,System.ComponentModel.CancelEventArgs e){if(running){e.Cancel=true;closeAfter=true;if(stop!=null)stop.Cancel();}};
  text.Text=String.Join("\n",models.Select(x=>x.name+" · "+(x.bytes/1048576.0).ToString("0.0")+" MiB"))+"\n\nTotal: "+(models.Sum(x=>x.bytes)/1048576.0).ToString("0.0")+" MiB. Existing verified files are reused.";
  if(automatic)Loaded+=async delegate{if(automaticStarted)return;automaticStarted=true;await Prepare();};
 }
 void RequestCancel(bool close){Ready=false;if(close)closeAfter=true;if(stop!=null){cancel.IsEnabled=false;text.Text="Cancelling — waiting for preparation to stop…";stop.Cancel();}}
 public void CancelAndClose(){if(running)RequestCancel(true);else Close();}
 async Task Prepare(){if(running)return;running=true;Ready=false;FailureMessage=null;download.IsEnabled=false;cancel.IsEnabled=true;stop=new CancellationTokenSource();var token=stop.Token;
  try{foreach(var model in models){text.Text="Checking / downloading "+model.name+"…";progress.Value=0;progress.IsIndeterminate=true;
    Action<ModelSpec,CancellationToken,Action<long>> transfer=ModelStore.Download;
#if AUTO_PREPARATION_REGRESSION
    if(DownloadOverride!=null)transfer=DownloadOverride;
#endif
    await Task.Factory.StartNew(()=>transfer(model,token,received=>Dispatcher.BeginInvoke(new Action(delegate{if(token.IsCancellationRequested)return;progress.IsIndeterminate=false;progress.Value=100.0*received/model.bytes;text.Text=model.name+" · "+(received/1048576.0).ToString("0.0")+" / "+(model.bytes/1048576.0).ToString("0.0")+" MiB";}))));}
   token.ThrowIfCancellationRequested();bool verified=await Task.Factory.StartNew(()=>models.All(ModelStore.Verified));token.ThrowIfCancellationRequested();if(!verified)throw new IOException("Prepared models did not pass the final integrity check.");Ready=true;
   progress.Value=100;text.Text="All models are verified and ready. You can close this window and enhance images offline.";
  }catch(OperationCanceledException){FailureMessage="Model preparation cancelled. Completed files are kept.";text.Text=FailureMessage+" Choose Download to retry.";}
   catch(Exception error){FailureMessage="Models are not ready: "+error.Message;text.Text=FailureMessage+"\nCheck your connection, or close another Models window, then retry.";}
   finally{running=false;progress.IsIndeterminate=false;download.IsEnabled=true;cancel.IsEnabled=false;stop.Dispose();stop=null;
#if AUTO_PREPARATION_REGRESSION
    if(PreparationFinishedOverride!=null)PreparationFinishedOverride(this);
#endif
    if((closeAfter||automatic&&Ready)&&IsVisible)Close();}
 }
}
}
