using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
namespace NCF {
public sealed partial class MainWindow {
 string displayedPath,displayedRevision,displayedResult;
 ImageDocument pendingViewDocument;
 string pendingViewPath,pendingViewRevision,pendingViewResult;
 bool observedRefreshScheduled;
 void SyncDocumentState(){if(document==null)return;sourcePath=document.Path;resultPath=document.Result;savedPath=document.Saved;resultScale=document.ResultScale;dirty=document.Unsaved;}
 void OnFolderRefreshed(int previousIndex){
  if(allowClose||commitCloseScheduled||browser==null||observedRefreshScheduled)return;
  observedRefreshScheduled=true;
  Later(new Action(async delegate{try{while(fileWork||loading){if(allowClose)return;await Task.Delay(40);}if(allowClose||closingFlow||closeWhenDone)return;await ReconcileSelectedView(previousIndex);}finally{observedRefreshScheduled=false;}}));
 }
 async Task ReconcileSelectedView(int previousIndex){
  if(browser==null||allowClose)return;SyncDocumentState();var selected=browser.Current;
  if(selected!=null&&!selected.Missing){
   bool pending=pendingViewDocument==selected&&pendingViewPath==selected.Path&&pendingViewRevision==selected.Revision&&pendingViewResult==selected.Result;
   if(!pending&&(selected!=document||displayedPath!=selected.Path||displayedRevision!=selected.Revision||displayedResult!=selected.Result))await LoadDocument(selected,true);
   else Refresh();return;
  }
  var available=browser.Visible().Where(d=>!d.Missing).ToList();
  if(available.Count>0){var next=available[Math.Max(0,Math.Min(previousIndex,available.Count-1))];sidebar.Selected.Clear();sidebar.Selected.Add(next);await LoadDocument(next,true);sidebar.Reveal(next);return;}
  // Keep pending document/result references for Save, while the unavailable
  // original is never falsely represented by its enhanced PNG.
  StoreDocument();document=selected;sourcePath=selected==null?null:selected.Path;resultPath=selected==null?null:selected.Result;savedPath=selected==null?null:selected.Saved;dirty=selected!=null&&selected.Unsaved;
  loadGeneration++;pendingViewDocument=null;canvas.IsLoading=false;canvas.SetImages(null,null,null);Refresh();
 }
 async Task ShowDocument(ImageDocument target){await LoadDocument(target,false);}
 async Task LoadDocument(ImageDocument target,bool reload){
  if(target==null||allowClose||loading)return;
  if(!reload&&target==document){browser.Current=target;loadGeneration++;pendingViewDocument=null;canvas.IsLoading=false;canvas.InvalidateVisual();SyncDocumentState();Refresh();return;}
  StoreDocument();browser.Current=target;int generation=++loadGeneration;string path=target.Path,revision=target.Revision,result=target.Result;bool missing=target.Missing;
  pendingViewDocument=target;pendingViewPath=path;pendingViewRevision=revision;pendingViewResult=result;
  canvas.IsLoading=true;canvas.InvalidateVisual();Refresh();status.Text="Loading "+Path.GetFileName(path)+"…";
  BitmapSource original=null,enhanced=null;Exception originalError=null,resultError=null;
  try{
   using(ownedSession.Acquire()){await Task.Factory.StartNew(delegate{try{if(!File.Exists(path))throw new FileNotFoundException("The original image is unavailable.");original=LoadForViewer(path);}catch(Exception e){originalError=e;}if(result!=null)try{enhanced=LoadBitmap(result);}catch(Exception e){resultError=e;}});}
   if(generation!=loadGeneration||allowClose)return;
   if(target.Missing!=missing){pendingViewDocument=null;await ReconcileSelectedView(sidebar.Surface.Items.IndexOf(target));return;}
   if(target.Path!=path||target.Revision!=revision||target.Result!=result){pendingViewDocument=null;if(browser.Current==target)await LoadDocument(target,true);return;}
   document=target;SyncDocumentState();switching=true;model.SelectedItem=target.Preset;scale.SelectedIndex=Array.IndexOf(new[]{1,2,4},target.Scale);for(int k=0;k<3;k++)scales[k].IsChecked=k==scale.SelectedIndex;switching=false;
   displayedPath=path;displayedRevision=revision;displayedResult=result;
   if(originalError!=null){canvas.SetImages(null,null,null);ShowError("Could not display the original image. Any enhanced result remains available for saving.\n\n"+originalError.Message);}
   else{canvas.SetImages(original,enhanced,target.Position);target.Pixels=new Size(original.PixelWidth,original.PixelHeight);if(resultError!=null)ShowError("Could not display the enhanced image. Its temporary file has been retained.\n\n"+resultError.Message);}
  }catch(Exception e){if(generation==loadGeneration&&!allowClose)ShowError("Could not load this image.\n\n"+e.Message);}
  finally{if(generation==loadGeneration){pendingViewDocument=null;canvas.IsLoading=false;canvas.InvalidateVisual();Refresh();}}
 }
 static void ProtectOriginalIdentities(string[] identities,string destination){if(File.Exists(destination)&&identities.Contains(FileIdentity.Read(destination)))throw new IOException("The output points to an original image observed in this session.");}
 void ProtectObservedOriginal(ImageDocument target,string destination){if(target!=null)ProtectOriginalIdentities(target.ObservedOriginalIdentities.ToArray(),destination);}
}
}
