using System;
using System.IO;
using System.Linq;
namespace NCF {
// Exclusive .lock is held until owner AND all asynchronous users have finished.
// No cleanup of older, unmarked sessions: they may belong to an older live build.
public sealed class TemporarySession : IDisposable {
 public readonly string DirectoryPath;
 readonly string root;
 readonly FileStream sessionLock;
 readonly object sync=new object();
 int users=1;bool closed;
#if CLOSE_REGRESSION
 public static string RegressionRoot;
#endif
 public static string DefaultRoot {get{
#if CLOSE_REGRESSION
  if(!String.IsNullOrEmpty(RegressionRoot))return Path.GetFullPath(RegressionRoot);
#endif
  return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NCF Image Upscaler","sessions");}}
 public TemporarySession(string parent){root=Path.GetFullPath(parent);Directory.CreateDirectory(root);VerifyChain(root);DirectoryPath=Path.Combine(root,Guid.NewGuid().ToString("N"));if(Directory.Exists(DirectoryPath))throw new IOException("Temporary session name is occupied.");Directory.CreateDirectory(DirectoryPath);try{sessionLock=new FileStream(Path.Combine(DirectoryPath,".lock"),FileMode.CreateNew,FileAccess.ReadWrite,FileShare.Delete);sessionLock.WriteByte(1);sessionLock.Flush(true);}catch{try{Directory.Delete(DirectoryPath,false);}catch{}throw;}}
 public IDisposable Acquire(){lock(sync){if(closed)throw new ObjectDisposedException("Temporary image session");users++;return new Lease(this);}}
 sealed class Lease : IDisposable {TemporarySession owner;public Lease(TemporarySession value){owner=value;}public void Dispose(){var value=System.Threading.Interlocked.Exchange(ref owner,null);if(value!=null)value.Release();}}
 public void Dispose(){lock(sync){if(closed)return;closed=true;}Release();}
 void Release(){bool remove;lock(sync){users--;remove=users==0;}if(!remove)return;bool ready=false;try{ready=PrepareRemove(root,DirectoryPath);}finally{sessionLock.Dispose();}if(ready)FinishRemove(root,DirectoryPath);}
 static void VerifyChain(string path){for(string p=Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)){if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("Temporary image storage cannot use symbolic links or junctions.");}}
 static bool Valid(string root,string directory){Guid guid;string full=Path.GetFullPath(directory);return Guid.TryParseExact(Path.GetFileName(full),"N",out guid)&&String.Equals(Path.GetDirectoryName(full),Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase);}
 static void DeleteContents(string directory,bool preserveLock){foreach(string entry in Directory.EnumerateFileSystemEntries(directory)){if(preserveLock&&Path.GetFileName(entry)==".lock")continue;var attributes=File.GetAttributes(entry);if((attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Refusing to follow a link inside temporary storage.");if((attributes&FileAttributes.Directory)!=0){DeleteContents(entry,false);Directory.Delete(entry,false);}else File.Delete(entry);}}
 static bool PrepareRemove(string root,string path){try{if(!Valid(root,path))return false;VerifyChain(path);DeleteContents(path,true);return true;}catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}}
 static bool FinishRemove(string root,string path){try{if(!Valid(root,path))return false;VerifyChain(path);string marker=Path.Combine(path,".lock");if((File.GetAttributes(marker)&FileAttributes.ReparsePoint)!=0)return false;File.Delete(marker);Directory.Delete(path,false);return true;}catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}}
 public static int RemoveAbandoned(string parent){string root=Path.GetFullPath(parent);if(!Directory.Exists(root))return 0;try{VerifyChain(root);}catch(IOException){return 0;}int removed=0;foreach(var child in Directory.EnumerateDirectories(root)){if(!Valid(root,child))continue;try{VerifyChain(child);string marker=Path.Combine(child,".lock");if(!File.Exists(marker)||(File.GetAttributes(marker)&FileAttributes.ReparsePoint)!=0)continue;bool ready;using(var held=new FileStream(marker,FileMode.Open,FileAccess.ReadWrite,FileShare.Delete)){if(held.Length!=1||held.ReadByte()!=1)continue;ready=PrepareRemove(root,child);}if(ready&&FinishRemove(root,child))removed++;}catch(IOException){}catch(UnauthorizedAccessException){}}return removed;}
}
}
