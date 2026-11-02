using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media.Imaging;
namespace NCF {
public sealed partial class FolderSidebar {
 public Func<string[],CancellationToken,Dictionary<string,Size>> MetadataLoader;
 public bool PreparingGrid {get{return Surface.Preparing;}}
 public int MetadataBatches {get{return metadataBatches;}}
 public bool SkeletonAnimationRunning {get{return pulse.IsEnabled;}}
 readonly Dictionary<ImageDocument,string> metadataAttempts=new Dictionary<ImageDocument,string>();
 readonly Dictionary<ImageDocument,string> imageVersions=new Dictionary<ImageDocument,string>();
 readonly CancellationTokenSource metadataStop=new CancellationTokenSource();
 TemporarySession lifetime;int metadataBatches;
 void InvalidateRevision(ImageDocument d){metadataAttempts.Remove(d);imageVersions.Remove(d);Surface.SourceSizes.Remove(d);Surface.Failed.Remove(d);}
 void EnsureMetadata(){
  if(disposed||Session==null||MetadataLoader==null||!Surface.Adaptive||collapsed)return;
  var pending=Session.Visible().Where(d=>!metadataAttempts.ContainsKey(d)||metadataAttempts[d]!=d.Revision).Select(d=>new KeyValuePair<ImageDocument,string>(d,d.Revision)).ToArray();
  if(pending.Length==0)return;foreach(var item in pending)metadataAttempts[item.Key]=item.Value;
  metadataBatches++;Surface.Preparing=true;ReadMetadata(pending,Session);
 }
 async void ReadMetadata(KeyValuePair<ImageDocument,string>[] pending,BrowserSession owner){
  var sizes=new Dictionary<string,Size>(StringComparer.OrdinalIgnoreCase);
  try{using(lifetime.Acquire()){sizes=await Task.Factory.StartNew(()=>MetadataLoader(pending.Select(p=>p.Key.Path).ToArray(),metadataStop.Token));}}
  catch(OperationCanceledException){}catch(IOException){}catch(UnauthorizedAccessException){}catch(NotSupportedException){}catch(ObjectDisposedException){}
  finally{metadataBatches--;if(!disposed&&Session==owner){foreach(var item in pending){Size size;if(item.Key.Revision==item.Value&&Session.Documents.Contains(item.Key)&&sizes.TryGetValue(item.Key.Path,out size)&&size.Width>0&&size.Height>0){Surface.SourceSizes[item.Key]=size;item.Key.Pixels=size;}}Relayout(true);}}
 }
 Size LayoutSize(ImageDocument d,int index){Size size;if(Surface.SourceSizes.TryGetValue(d,out size))return size;if(metadataBatches>0)return new[]{new Size(1200,1200),new Size(2400,1000),new Size(1000,3200),new Size(1200,1200)}[index%4];return new Size();}
 void QueueRequest(ImageDocument d){string version;if(disposed||cache==null||loading.Contains(d)||Surface.Failed.Contains(d)||Surface.Images.ContainsKey(d)&&imageVersions.TryGetValue(d,out version)&&version==d.Revision)return;loading.Add(d);Surface.Loading.Add(d);Dispatcher.BeginInvoke(new Action(()=>Request(d)));}
 void UpdateSkeletonAnimation(){if(!disposed&&Surface.IsVisible&&Surface.HasVisibleSkeleton&&SystemParameters.ClientAreaAnimation)pulse.Start();else pulse.Stop();}
}
}
