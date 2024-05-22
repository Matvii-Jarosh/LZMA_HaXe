package sevenZip;

import haxe.Int64;

interface ICodeProgress 
{
	public function setProgress(inSize:Int64, outSize:Int64):Void;
}