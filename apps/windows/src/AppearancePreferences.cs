using System;
using System.IO;
using System.Text;
namespace NCF {
// A separate preference file avoids modifying sidebar or per-image/session state.
public static class AppearancePreferences {
 static readonly string[] names={"Soft","Fluent","Studio"};
 static readonly object gate=new object();
 static string PreferencePath {get{
#if CLOSE_REGRESSION
  if(TemporarySession.RegressionRoot!=null)return Path.Combine(TemporarySession.RegressionRoot,"appearance.preferences");
#endif
  return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NCF Image Upscaler","appearance.preferences");
 }}
 public static int ReadIndex(){lock(gate){try{string value=File.ReadAllText(PreferencePath,Encoding.UTF8).Trim();int index=Array.IndexOf(names,value);return index<0?0:index;}catch{return 0;}}}
 public static bool TrySave(int index,out string error){
  error=null;if(index<0||index>=names.Length){error="Unknown appearance.";return false;}
  lock(gate){string temporary=null;try{string target=PreferencePath;Directory.CreateDirectory(Path.GetDirectoryName(target));temporary=target+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllText(temporary,names[index]+"\n",new UTF8Encoding(false));if(File.Exists(target))File.Replace(temporary,target,null);else File.Move(temporary,target);return true;}catch(Exception exception){error=exception.Message;return false;}finally{if(temporary!=null)try{if(File.Exists(temporary))File.Delete(temporary);}catch{}}}
 }
}
}
