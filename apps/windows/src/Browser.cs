using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;

namespace NCF {
public sealed class ImageDocument {
 public string Path,Result,Saved,Revision,Identity;
 public readonly HashSet<string> ObservedOriginalIdentities=new HashSet<string>();
 public string Preset="Photo",WorkState="";
 public int Scale=4,ResultScale=4;
 public double WorkProgress;
 public Size Pixels;
 public ViewPosition Position;
 public bool Processing,Missing;
 public bool Unsaved {get{return Result!=null&&Saved==null;}}
 public ImageDocument(string path){Path=path;Update();}
 public void Update(){if(Saved!=null&&!File.Exists(Saved))Saved=null;if(!File.Exists(Path)){Missing=true;return;}Missing=false;var f=new FileInfo(Path);Identity=FileIdentity.Read(Path);ObservedOriginalIdentities.Add(Identity);Revision=Identity+"/"+f.Length+"/"+f.LastWriteTimeUtc.Ticks+"/"+f.CreationTimeUtc.Ticks;}
}
public static class FileIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint Attr;public System.Runtime.InteropServices.ComTypes.FILETIME Created,Access,Written;public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(IntPtr handle,out Info value);
 public static string Read(string path){try{using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){Info i;if(!GetFileInformationByHandle(f.SafeFileHandle.DangerousGetHandle(),out i))return path;return i.Volume+":"+i.IndexHigh+":"+i.IndexLow;}}catch{return path;}}
}
public static class BrowserLayout {
 public static List<Rect> Calculate(double width,double size,bool adaptive,IList<Size> images){
  double usable=Math.Max(1,width-16);int columns=Math.Max(1,(int)Math.Floor((usable+10)/(size+26)));double cw=Math.Floor((usable-(columns-1)*10)/columns),ch=adaptive?cw-16+58:size+58;
  var free=new int[columns];int cursorRow=0,cursorColumn=0;var result=new List<Rect>();
  foreach(var p in images){int cs=1,rs=1;if(adaptive&&p.Width>0&&p.Height>0&&Math.Max(p.Width,p.Height)/Math.Min(p.Width,p.Height)>1.6){double pw=Math.Max(1,cw-16),ph=Math.Max(1,ch-58);if(p.Width/p.Height>pw/ph)cs=(int)Math.Min(columns,Math.Max(1,Math.Ceiling((p.Width*Math.Min(1,ph/p.Height)+26)/(cw+10)-1e-9)));else rs=(int)Math.Min(100000,Math.Max(1,Math.Ceiling((p.Height*Math.Min(1,pw/p.Width)+68)/(ch+10)-1e-9)));}
   int best=int.MaxValue,column=0;for(int c=0;c<=columns-cs;c++){int row=cursorRow+(c<cursorColumn?1:0);for(int k=c;k<c+cs;k++)row=Math.Max(row,free[k]);if(row<best){best=row;column=c;}}
   cursorRow=best;cursorColumn=column+cs;if(cursorColumn==columns){cursorRow++;cursorColumn=0;}for(int k=column;k<column+cs;k++)free[k]=best+rs;
   result.Add(new Rect(8+column*(cw+10),8+best*(ch+10),cs*(cw+10)-10,rs*(ch+10)-10));
  }return result;
 }
}
public static class BrowserNavigation {
 public static int Page(int current,IList<Rect> frames,double height,bool down){if(current<0||current>=frames.Count)return down?0:frames.Count-1;var origin=frames[current];double target=origin.Top+(down?1:-1)*Math.Max(1,height);return Enumerable.Range(0,frames.Count).Where(i=>down?i>current:i<current).OrderBy(i=>Math.Abs(frames[i].Top-target)).ThenBy(i=>Math.Abs(frames[i].Left+frames[i].Width/2-origin.Left-origin.Width/2)).ThenBy(i=>Math.Abs(i-current)).DefaultIfEmpty(current).First();}
 public static int Arrow(int current,IList<Rect> frames,System.Windows.Input.Key key){if(current<0||current>=frames.Count)return 0;var from=frames[current];bool horizontal=key==System.Windows.Input.Key.Left||key==System.Windows.Input.Key.Right;int sign=key==System.Windows.Input.Key.Left||key==System.Windows.Input.Key.Up?-1:1;Func<Rect,double> along=r=>horizontal?r.Left+r.Width/2:r.Top+r.Height/2;Func<Rect,double> across=r=>horizontal?r.Top+r.Height/2:r.Left+r.Width/2;Func<Rect,bool> overlaps=r=>horizontal?r.Bottom>from.Top&&r.Top<from.Bottom:r.Right>from.Left&&r.Left<from.Right;return Enumerable.Range(0,frames.Count).Where(i=>(along(frames[i])-along(from))*sign>0).OrderBy(i=>overlaps(frames[i])?0:1).ThenBy(i=>Math.Abs(along(frames[i])-along(from))).ThenBy(i=>Math.Abs(across(frames[i])-across(from))).ThenBy(i=>Math.Abs(i-current)).DefaultIfEmpty(current).First();}
 public static double RevealOffset(Rect frame,double top,double height){double bottom=top+height;if(frame.Bottom<=top)return Math.Max(0,frame.Bottom-height);if(frame.Top>=bottom)return Math.Max(0,frame.Top);if(frame.Height>height)return top;if(frame.Top<top)return Math.Max(0,frame.Top);if(frame.Bottom>bottom)return Math.Max(0,frame.Bottom-height);return top;}
}
public sealed class BrowserSession : IDisposable {
 public readonly string Folder;
 public readonly List<ImageDocument> Documents=new List<ImageDocument>();
 public ImageDocument Current;
 public string Filter="";
 public int SortKey;public bool Descending;
 public Action Changed;
 readonly FileSystemWatcher watcher;
 public BrowserSession(string path){Folder=System.IO.Path.GetFullPath(path);Refresh();watcher=new FileSystemWatcher(Folder){NotifyFilter=NotifyFilters.FileName|NotifyFilters.Size|NotifyFilters.LastWrite|NotifyFilters.CreationTime};watcher.Changed+=Signal;watcher.Created+=Signal;watcher.Deleted+=Signal;watcher.Renamed+=Signal;watcher.EnableRaisingEvents=true;}
 void Signal(object s,FileSystemEventArgs e){var a=Changed;if(a!=null)a();}
 public static bool Supported(string p){return new[]{".png",".jpg",".jpeg",".tif",".tiff",".bmp",".webp"}.Contains(System.IO.Path.GetExtension(p).ToLowerInvariant());}
 public void Refresh(){
  var files=Directory.EnumerateFiles(Folder).Where(p=>Supported(p)&&(File.GetAttributes(p)&(FileAttributes.Hidden|FileAttributes.Directory))==0).ToList();
  var paths=new HashSet<string>(files,StringComparer.OrdinalIgnoreCase);var unmatched=Documents.Where(d=>!paths.Contains(d.Path)).ToList();
  foreach(var p in files){var old=Documents.FirstOrDefault(d=>String.Equals(d.Path,p,StringComparison.OrdinalIgnoreCase));if(old==null){string id=FileIdentity.Read(p);var matches=unmatched.Where(d=>d.Identity==id).ToList();if(matches.Count==1){old=matches[0];unmatched.Remove(old);}else{old=new ImageDocument(p);Documents.Add(old);}}old.Path=p;old.Update();}
  foreach(var d in unmatched){d.Update();if(!d.Unsaved&&!d.Processing)Documents.Remove(d);}if(Current!=null&&!Documents.Contains(Current))Current=null;
 }
 public List<ImageDocument> Visible(){var a=Documents.Where(d=>System.IO.Path.GetFileName(d.Path).IndexOf(Filter.Trim(),StringComparison.OrdinalIgnoreCase)>=0).ToList();a.Sort(Compare);return a;}
 int Compare(ImageDocument a,ImageDocument b){int n=0;var x=new FileInfo(a.Path);var y=new FileInfo(b.Path);try{switch(SortKey){case 1:n=x.LastWriteTimeUtc.CompareTo(y.LastWriteTimeUtc);break;case 2:n=x.CreationTimeUtc.CompareTo(y.CreationTimeUtc);break;case 3:n=x.Length.CompareTo(y.Length);break;case 4:n=StringComparer.OrdinalIgnoreCase.Compare(x.Extension,y.Extension);break;}}catch{}if(n==0)n=Natural(System.IO.Path.GetFileName(a.Path),System.IO.Path.GetFileName(b.Path));return Descending?-n:n;}
 [DllImport("shlwapi.dll",CharSet=CharSet.Unicode)]static extern int StrCmpLogicalW(string x,string y);
 public static int Natural(string a,string b){return StrCmpLogicalW(a,b);}
 public void Dispose(){watcher.Dispose();}
}
}
