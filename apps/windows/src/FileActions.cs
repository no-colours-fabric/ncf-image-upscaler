using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using VB=Microsoft.VisualBasic.FileIO;
namespace NCF {
public sealed partial class MainWindow {
 sealed class Change {public string Name;public Action Undo,Redo;}
 readonly Stack<Change> undo=new Stack<Change>(),redo=new Stack<Change>();
 bool fileWork;
 List<ImageDocument> Targets(bool viewer){return viewer?document==null?new List<ImageDocument>():new List<ImageDocument>{document}:sidebar.Selected.ToList();}
 void InstallFileActions(){
  sidebar.Surface.ContextMenu=new ContextMenu();sidebar.Surface.ContextMenuOpening+=delegate{FillMenu(sidebar.Surface.ContextMenu,false);};canvas.ContextMenu=new ContextMenu();canvas.ContextMenuOpening+=delegate{FillMenu(canvas.ContextMenu,true);};
  sidebar.Import=async paths=>await ImportFiles(paths,false);
  PreviewKeyDown+=async delegate(object sender,KeyEventArgs e){if(e.Handled||e.OriginalSource is TextBox||e.OriginalSource is ComboBox)return;bool control=(Keyboard.Modifiers&ModifierKeys.Control)!=0,shift=(Keyboard.Modifiers&ModifierKeys.Shift)!=0,alt=(Keyboard.Modifiers&ModifierKeys.Alt)!=0;var targets=Targets(!sidebar.Surface.IsKeyboardFocusWithin);
   if(control&&e.Key==Key.C){if(shift)CopyPaths(targets);else CopyFiles(targets);}
   else if(control&&e.Key==Key.V){if(alt)await Paste(true);else await Paste(false);}
   else if(control&&e.Key==Key.D)await Duplicate(targets);
   else if(e.Key==Key.F2&&Keyboard.Modifiers==ModifierKeys.None)await Rename(targets);
   else if(e.Key==Key.Delete&&!control)await RemoveFiles(targets,shift);
   else if(control&&e.Key==Key.A){if(shift)sidebar.Selected.Clear();else foreach(var d in browser.Visible())sidebar.Selected.Add(d);sidebar.Surface.InvalidateVisual();UpdateStatus();}
   else if(control&&e.Key==Key.Z)await History(shift);else if(control&&e.Key==Key.Y)await History(true);
   else if(control&&e.Key==Key.R)RevealFiles(targets);
   else if(alt&&e.SystemKey==Key.Enter)Properties(targets);
   else return;e.Handled=true;
  };
 }
 void FillMenu(ContextMenu menu,bool viewer){menu.Items.Clear();var targets=Targets(viewer);bool any=targets.Count>0,one=targets.Count==1,safe=any&&!targets.Any(d=>d.Processing)&&!fileWork;Action<string,Action,bool> add=(name,action,enabled)=>{var item=new MenuItem{Header=name,IsEnabled=enabled};item.Click+=delegate{try{action();}catch(Exception e){ShowError(e.Message);}};menu.Items.Add(item);};Action sep=()=>menu.Items.Add(new Separator());
  add("Copy Files",()=>CopyFiles(targets),any);add("Copy Image",()=>CopyImage(targets[0],false),one);if(targets.Any(d=>d.Result!=null))add("Copy Enhanced Image",()=>CopyImage(targets[0],true),one&&targets[0].Result!=null);add("Copy Paths",()=>CopyPaths(targets),any);sep();
  add("Paste into This Folder",async()=>await Paste(false),browser!=null&&!fileWork&&!closeWhenDone);add("Move Items Here",async()=>await Paste(true),browser!=null&&!busy&&!fileWork);sep();
  add("Rename…",async()=>await Rename(targets),one&&safe);add("Duplicate",async()=>await Duplicate(targets),any&&!fileWork);sep();
  if(targets.Any(d=>d.Unsaved)){add("Save Enhancements",async()=>await ResolveBatch(targets,false),safe);add("Discard Unsaved Enhancements…",async()=>await ResolveBatch(targets,true),safe);sep();}
  add("Show in Explorer",()=>RevealFiles(targets),any);add("Properties…",()=>Properties(targets),any);
  var openWith=new MenuItem{Header="Open With",IsEnabled=any};var standard=new MenuItem{Header="Choose an application…"};standard.Click+=delegate{try{foreach(var d in targets)Process.Start(new ProcessStartInfo("rundll32.exe","shell32.dll,OpenAs_RunDLL "+Quote(d.Path)){UseShellExecute=true});}catch(Exception e){ShowError(e.Message);}};openWith.Items.Add(standard);var other=new MenuItem{Header="Other Application…"};other.Click+=delegate{var picker=new OpenFileDialog{Filter="Application|*.exe",Title="Open With"};if(picker.ShowDialog(this)==true)foreach(var d in targets)Process.Start(new ProcessStartInfo(picker.FileName,Quote(d.Path)){UseShellExecute=true});};openWith.Items.Add(other);menu.Items.Add(openWith);sep();
  add("Move to Recycle Bin",async()=>await RemoveFiles(targets,false),safe);add("Delete Permanently…",async()=>await RemoveFiles(targets,true),safe);sep();
  add("Select All",()=>{foreach(var d in browser.Visible())sidebar.Selected.Add(d);sidebar.Surface.InvalidateVisual();UpdateStatus();},browser!=null);add("Deselect All",()=>{sidebar.Selected.Clear();sidebar.Surface.InvalidateVisual();UpdateStatus();},any);add("Refresh Folder",RefreshFolder,browser!=null&&!fileWork&&!closeWhenDone);
 }
 void CopyFiles(List<ImageDocument> targets){if(targets.Count==0)return;var list=new StringCollection();list.AddRange(targets.Where(d=>File.Exists(d.Path)).Select(d=>d.Path).ToArray());Clipboard.SetFileDropList(list);}
 void CopyPaths(List<ImageDocument> targets){if(targets.Count>0)Clipboard.SetText(String.Join(Environment.NewLine,targets.Select(d=>d.Path)));}
 void CopyImage(ImageDocument d,bool enhanced){var image=LoadAsset(enhanced?d.Result:d.Path);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(image));var stream=new MemoryStream();encoder.Save(stream);stream.Position=0;var data=new DataObject();data.SetData("PNG",stream);data.SetImage(image);Clipboard.SetDataObject(data,true);}
 async Task Paste(bool move){if(browser==null||fileWork||move&&busy)return;if(Clipboard.ContainsFileDropList()){await ImportFiles(Clipboard.GetFileDropList().Cast<string>().ToArray(),move);return;}if(move)return;BitmapSource image=null;var data=Clipboard.GetDataObject();if(data!=null&&data.GetDataPresent("PNG")){var value=data.GetData("PNG");var stream=value as Stream;if(stream!=null){stream.Position=0;image=BitmapFrame.Create(stream,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);image.Freeze();}}if(image==null&&Clipboard.ContainsImage())image=Clipboard.GetImage();if(image!=null){string target=Available(browser.Folder,"Image.png",false);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using(var output=new FileStream(target,FileMode.CreateNew))png.Save(output);RecordCopy(target);RefreshFolder();await OpenPath(target);}}
 public static string Available(string directory,string name,bool copy){string stem=Path.GetFileNameWithoutExtension(name)+(copy?" copy":""),ext=Path.GetExtension(name),path=Path.Combine(directory,stem+ext);int n=2;while(File.Exists(path)||Directory.Exists(path))path=Path.Combine(directory,stem+"_"+(n++)+ext);return path;}
 void Record(Change change){undo.Push(change);redo.Clear();}
 static string Fingerprint(string path){using(var hash=System.Security.Cryptography.SHA256.Create())using(var input=File.OpenRead(path))return Convert.ToBase64String(hash.ComputeHash(input));}
 void RecordCopy(string path){string backup=Path.Combine(session,"undo-"+Guid.NewGuid().ToString("N")+Path.GetExtension(path));File.Copy(path,backup,false);string revision=FileIdentity.Read(path),digest=Fingerprint(path);Record(new Change{Name="Copy",Undo=()=>{if(FileIdentity.Read(path)!=revision||Fingerprint(path)!=digest)throw new IOException("The copied file was changed or replaced; undo refused.");File.Delete(path);},Redo=()=>{File.Copy(backup,path,false);revision=FileIdentity.Read(path);}});}
 async Task ImportFiles(string[] paths,bool move){if(browser==null||fileWork||move&&busy)return;fileWork=true;var errors=new List<string>();try{foreach(string input in paths){try{if(!File.Exists(input)||!BrowserSession.Supported(input))throw new IOException("Not a supported image file.");if(move&&String.Equals(Path.GetDirectoryName(Path.GetFullPath(input)),browser.Folder,StringComparison.OrdinalIgnoreCase))continue;string source=Path.GetFullPath(input),target=Available(browser.Folder,Path.GetFileName(input),String.Equals(Path.GetDirectoryName(source),browser.Folder,StringComparison.OrdinalIgnoreCase));await Task.Factory.StartNew(()=>{if(move)File.Move(source,target);else File.Copy(source,target,false);});if(move)RecordMove(source,target);else RecordCopy(target);}catch(Exception e){errors.Add(Path.GetFileName(input)+": "+e.Message);}}}finally{fileWork=false;RefreshFolder();}if(closeWhenDone)await FinishClose();if(errors.Count>0)ShowError(String.Join("\n",errors));}
 async Task Duplicate(List<ImageDocument> targets){await ImportFiles(targets.Select(d=>d.Path).ToArray(),false);}
 void RecordMove(string from,string to){Record(new Change{Name="Move",Undo=()=>File.Move(to,from),Redo=()=>File.Move(from,to)});}
 async Task Rename(List<ImageDocument> targets){if(targets.Count!=1||targets[0].Processing||fileWork)return;var d=targets[0];string name=Input("Rename Image",Path.GetFileName(d.Path));if(name==null||name==Path.GetFileName(d.Path))return;if(name!=Path.GetFileName(name)||name.IndexOfAny(Path.GetInvalidFileNameChars())>=0){ShowError("Choose a valid filename without a directory.");return;}if(!String.Equals(Path.GetExtension(name),Path.GetExtension(d.Path),StringComparison.OrdinalIgnoreCase)&&Choice("Change file extension?","Changing the extension may prevent this image from opening.",new[]{"Change Extension","Cancel"})!=0)return;string source=d.Path,target=Path.Combine(browser.Folder,name);try{await Task.Factory.StartNew(()=>File.Move(source,target));d.Path=target;if(d==document)sourcePath=target;d.Update();RecordMove(source,target);RefreshFolder();}catch(Exception e){ShowError(e.Message);}}
 string Input(string caption,string value){
#if CLOSE_REGRESSION
  if(InputOverride!=null)return InputOverride(caption,value);
#endif
  var w=new Window{Title=caption,Owner=this,Width=450,SizeToContent=SizeToContent.Height,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.CenterOwner,ShowInTaskbar=false};var panel=new StackPanel{Margin=new Thickness(20)};w.Content=panel;var text=new TextBox{Text=value,Margin=new Thickness(0,0,0,16)};panel.Children.Add(text);var buttons=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};panel.Children.Add(buttons);var ok=new Button{Content="Rename",IsDefault=true,Padding=new Thickness(15,6,15,6)};var cancelButton=new Button{Content="Cancel",IsCancel=true,Padding=new Thickness(15,6,15,6),Margin=new Thickness(8,0,0,0)};buttons.Children.Add(ok);buttons.Children.Add(cancelButton);ok.Click+=delegate{w.DialogResult=true;};w.Loaded+=delegate{text.Focus();text.SelectAll();};return w.ShowDialog()==true?text.Text:null;}
 async Task ResolveBatch(List<ImageDocument> targets,bool discard){if(targets.Any(d=>d.Processing))return;if(discard&&Choice("Discard unsaved enhancements?","Only the temporary enhanced results will be discarded. Original images and saved PNGs are retained.",new[]{"Discard Results","Cancel"})!=0)return;foreach(var d in targets.Where(d=>d.Unsaved).ToArray()){await ShowDocument(d);if(discard){string old=resultPath;resultPath=null;savedPath=null;dirty=false;d.Result=d.Saved=null;File.Delete(old);canvas.SetImages(canvas.Original,null,d.Position);}else if(!await SaveResult(false))break;}Refresh();}
 async Task RemoveFiles(List<ImageDocument> targets,bool permanent){if(targets.Count==0||fileWork||targets.Any(d=>d.Processing))return;foreach(var d in targets.Where(d=>d.Unsaved)){await ShowDocument(d);if(!await ResolveUnsaved())return;}if(permanent&&Choice("Delete permanently?","Permanently delete "+targets.Count+" original image(s)? This cannot be undone.",new[]{"Delete Permanently","Cancel"})!=0)return;fileWork=true;var errors=new List<string>();try{foreach(var d in targets){try{string path=d.Path;if(permanent)await Task.Factory.StartNew(()=>File.Delete(path));else{string backup=Path.Combine(session,"recycle-"+Guid.NewGuid().ToString("N")+Path.GetExtension(path));await Task.Factory.StartNew(()=>File.Copy(path,backup,false));VB.FileSystem.DeleteFile(path,VB.UIOption.OnlyErrorDialogs,VB.RecycleOption.SendToRecycleBin,VB.UICancelOption.ThrowException);Record(new Change{Name="Recycle",Undo=()=>File.Copy(backup,path,false),Redo=()=>VB.FileSystem.DeleteFile(path,VB.UIOption.OnlyErrorDialogs,VB.RecycleOption.SendToRecycleBin,VB.UICancelOption.ThrowException)});}d.Missing=true;browser.Documents.Remove(d);}catch(Exception e){errors.Add(Path.GetFileName(d.Path)+": "+e.Message);}}}finally{fileWork=false;RefreshFolder();}if(errors.Count>0)ShowError(String.Join("\n",errors));if(document!=null&&document.Missing){document=null;var next=browser.Visible().FirstOrDefault();if(next!=null)await ShowDocument(next);else{sourcePath=resultPath=savedPath=null;dirty=false;canvas.SetOriginal(null);Refresh();}}}
 async Task History(bool forward){if(busy||fileWork)return;var source=forward?redo:undo;var target=forward?undo:redo;if(source.Count==0)return;var change=source.Peek();fileWork=true;try{await Task.Factory.StartNew(()=>{if(forward)change.Redo();else change.Undo();});source.Pop();target.Push(change);RefreshFolder();}catch(Exception e){ShowError("Could not "+(forward?"redo":"undo")+" "+change.Name+".\n\n"+e.Message);}finally{fileWork=false;}}
 void RefreshFolder(){if(browser==null)return;int previous=sidebar.Surface.Items.IndexOf(browser.Current);browser.Refresh();SyncDocumentState();sidebar.Relayout(true);Refresh();OnFolderRefreshed(previous);}
 void RevealFiles(List<ImageDocument> targets){foreach(var d in targets)Process.Start(new ProcessStartInfo("explorer.exe","/select,"+Quote(d.Path)){UseShellExecute=true});}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct ShellInfo {public int Size;public uint Mask;public IntPtr Window;public string Verb,File,Parameters,Directory;public int Show;public IntPtr Instance,IDList;public string Class;public IntPtr Key;public uint HotKey;public IntPtr Icon,Process;}
 [DllImport("shell32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool ShellExecuteEx(ref ShellInfo info);
 void Properties(List<ImageDocument> targets){foreach(var d in targets){var info=new ShellInfo{Size=Marshal.SizeOf(typeof(ShellInfo)),Mask=12,Window=new System.Windows.Interop.WindowInteropHelper(this).Handle,Verb="properties",File=d.Path,Show=1};if(!ShellExecuteEx(ref info))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());}}
}
}
