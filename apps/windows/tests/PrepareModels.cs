using System;
using System.IO;
using System.Threading;
using NCF;
public static class PrepareModels {
 public static int Main(string[] args){try{ModelStore.Root=Path.GetFullPath(args[0]);foreach(var model in ModelStore.Read()){Console.WriteLine("Preparing "+model.id);ModelStore.Download(model,CancellationToken.None,bytes=>{});if(!ModelStore.Verified(model))throw new IOException("Integrity failure");Console.WriteLine("Verified "+model.id+" "+model.sha256);}return 0;}catch(Exception error){Console.Error.WriteLine(error);return 1;}}
}
