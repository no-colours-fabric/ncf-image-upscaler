using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media.Imaging;
namespace NCF {
public static class MetadataReader {
 public static Dictionary<string,Size> Read(string bundle,string session,string[] paths,CancellationToken stop){var sizes=new Dictionary<string,Size>(StringComparer.OrdinalIgnoreCase);var webp=new List<string>();foreach(string path in paths){stop.ThrowIfCancellationRequested();if(Path.GetExtension(path).Equals(".webp",StringComparison.OrdinalIgnoreCase)){webp.Add(path);continue;}try{using(var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){var decoder=BitmapDecoder.Create(input,BitmapCreateOptions.DelayCreation|BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.None);var frame=decoder.Frames[0];double w=frame.PixelWidth,h=frame.PixelHeight;int orientation=1;try{var meta=frame.Metadata as BitmapMetadata;if(meta!=null){object value=null;if(meta.ContainsQuery("/app1/ifd/{ushort=274}"))value=meta.GetQuery("/app1/ifd/{ushort=274}");else if(meta.ContainsQuery("/ifd/{ushort=274}"))value=meta.GetQuery("/ifd/{ushort=274}");if(value!=null)orientation=Convert.ToInt32(value);}}catch{}sizes[path]=orientation>=5&&orientation<=8?new Size(h,w):new Size(w,h);}}catch(IOException){}catch(NotSupportedException){}catch(FileFormatException){}}
  if(webp.Count==0)return sizes;stop.ThrowIfCancellationRequested();string request=Path.Combine(session,"metadata-"+Guid.NewGuid().ToString("N")+".json");File.WriteAllText(request,new JavaScriptSerializer().Serialize(webp),Encoding.UTF8);try{var info=new ProcessStartInfo(Path.Combine(bundle,"runtime","python.exe"),Quote(Path.Combine(bundle,"engine","asset.py"))+" --sizes "+Quote(request)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=bundle,StandardOutputEncoding=Encoding.UTF8};using(var process=Process.Start(info))using(stop.Register(delegate{try{if(!process.HasExited)process.Kill();}catch{}})){var error=System.Threading.Tasks.Task.Factory.StartNew(()=>process.StandardError.ReadToEnd());string output=process.StandardOutput.ReadToEnd();process.WaitForExit();string diagnostic=error.Result;stop.ThrowIfCancellationRequested();if(process.ExitCode!=0)throw new IOException("Could not read WebP dimensions. "+diagnostic);var data=new JavaScriptSerializer().Deserialize<Dictionary<string,int[]>>(output);foreach(var item in data)if(item.Value!=null&&item.Value.Length==2&&item.Value[0]>0&&item.Value[1]>0)sizes[item.Key]=new Size(item.Value[0],item.Value[1]);}}finally{File.Delete(request);}return sizes;
 }
 static string Quote(string path){return "\""+path+"\"";}
}
}
