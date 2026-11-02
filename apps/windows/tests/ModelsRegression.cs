using System;
using System.IO;
using System.Linq;
using System.Threading;
using NCF;
public static class ModelsRegression {
 static void Check(bool condition,string label){if(!condition)throw new Exception(label);Console.WriteLine("PASS "+label);}
 public static int Main(string[] args){try{
  ModelStore.Root=Path.GetFullPath(args[0]);Directory.CreateDirectory(ModelStore.Root);
  var fast=ModelStore.Read().Single(x=>x.id=="fast");
  using(var stop=new CancellationTokenSource()){
   bool cancelled=false;try{ModelStore.Download(fast,stop.Token,bytes=>{if(bytes>0)stop.Cancel();});}catch(OperationCanceledException){cancelled=true;}
   Check(cancelled&&!ModelStore.Present(fast),"Cancel does not publish an incomplete model");
   Check(!Directory.GetFiles(ModelStore.Root,"*.partial").Any(),"Cancel removes its staging file");
  }
  ModelStore.Download(fast,CancellationToken.None,bytes=>{});
  Check(ModelStore.Verified(fast),"Retry downloads and verifies pinned Fast");
  var path=Path.Combine(ModelStore.Root,fast.LocalName);var time=File.GetLastWriteTimeUtc(path);string originalRepo=fast.repository;fast.repository="invalid-owner/not-a-real-model";
  ModelStore.Download(fast,CancellationToken.None,bytes=>{});
  Check(File.GetLastWriteTimeUtc(path)==time,"Verified cache is reused without requesting the invalid URL");fast.repository=originalRepo;
  File.WriteAllBytes(path,new byte[]{1,2,3});
  ModelStore.Download(fast,CancellationToken.None,bytes=>{});
  Check(ModelStore.Verified(fast),"Corrupt cache is repaired atomically after verification");
  var wrong=new ModelSpec{id="wrong-hash",repository=fast.repository,revision=fast.revision,file=fast.file,bytes=fast.bytes,sha256=new string('0',64)};
  bool rejected=false;try{ModelStore.Download(wrong,CancellationToken.None,bytes=>{});}catch(IOException){rejected=true;}
  Check(rejected&&!ModelStore.Present(wrong),"Hash mismatch cannot become ready");
  Check(!Directory.GetFiles(ModelStore.Root,"*.partial").Any(),"Hash mismatch removes staging file");
  wrong.repository="ncf-deliberately-absent/no-such-model";bool failed=false;try{ModelStore.Download(wrong,CancellationToken.None,bytes=>{});}catch(System.Net.WebException){failed=true;}
  Check(failed&&!ModelStore.Present(wrong),"HTTP error remains actionable and does not publish");
  Check(ModelStore.Verified(fast),"Failed other download preserves completed Fast");
  return 0;
 }catch(Exception error){Console.Error.WriteLine(error);return 1;}}
}
