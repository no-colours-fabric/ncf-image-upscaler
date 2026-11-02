using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace NCF {
public sealed partial class MainWindow {
 bool preparingModels,windowClosed,startupPreparationAttempted;
 public bool PrepareModelsWhenLoaded {get;set;}
 CancellationTokenSource preparationCheck;
 ModelsWindow preparationWindow;
#if AUTO_PREPARATION_REGRESSION
 public Action<ModelsWindow> PreparationWindowOverride;
 public Action<string[]> WorkerArgumentsOverride;
#endif
 public async Task PrepareAtStartup(){
  if(startupPreparationAttempted||windowClosed||closeScheduled||allowClose)return;startupPreparationAttempted=true;
  while(loading&&!windowClosed&&!closeWhenDone)await Task.Delay(30);
  if(windowClosed||closeWhenDone)return;
  await PrepareModels(ModelStore.Read(),true,()=>!windowClosed&&!closeWhenDone&&!closeScheduled&&!allowClose);
 }
 async Task OpenModels(){if(busy||loading){ShowError("Wait for the current image operation, then open Models.");return;}await PrepareModels(ModelStore.Read(),false,()=>!windowClosed&&!closeWhenDone);}
 void CancelModelPreparation(){if(preparationCheck!=null)preparationCheck.Cancel();if(preparationWindow!=null)preparationWindow.CancelAndClose();}
 async Task<bool> PrepareModels(ModelSpec[] required,bool automatic,Func<bool> stillCurrent){
  if(preparingModels||windowClosed||closeWhenDone||closingFlow||closeScheduled||allowClose)return false;
  preparingModels=true;preparationCheck=new CancellationTokenSource();var token=preparationCheck.Token;Refresh();
  try{
   if(automatic){bool ready=await Task.Factory.StartNew(()=>{foreach(var spec in required){token.ThrowIfCancellationRequested();if(!ModelStore.Verified(spec))return false;}return true;});token.ThrowIfCancellationRequested();if(!stillCurrent())return false;if(ready)return true;}
   if(!stillCurrent())return false;
   preparationWindow=new ModelsWindow(this,automatic,required);
#if AUTO_PREPARATION_REGRESSION
   if(PreparationWindowOverride!=null)PreparationWindowOverride(preparationWindow);
#endif
   preparationWindow.ShowDialog();return preparationWindow.Ready&&!token.IsCancellationRequested&&stillCurrent();
  }catch(OperationCanceledException){return false;}
   catch(Exception error){if(!windowClosed&&!closeWhenDone)ShowError("Model preparation could not finish. Open Models to retry.\n\n"+error.Message);return false;}
   finally{preparationWindow=null;preparationCheck.Dispose();preparationCheck=null;preparingModels=false;if(!windowClosed)Refresh();}
 }
 static string PreparationSourceStamp(string path){try{if(!File.Exists(path))return null;var file=new FileInfo(path);return FileIdentity.Read(path)+"/"+file.Length+"/"+file.LastWriteTimeUtc.Ticks+"/"+file.CreationTimeUtc.Ticks;}catch(IOException){return null;}catch(UnauthorizedAccessException){return null;}}
}
}
