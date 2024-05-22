package sevenZip.compression.lz;

import haxe.io.Eof;

class InWindow {
    
    public var _bufferBase:haxe.io.Bytes; // pointer to buffer with data
    private var _stream:haxe.io.Input;
    private var _posLimit:Int; // offset (from _buffer) of first byte when new block reading must be done
    private var _streamEndWasReached:Bool; // if (true) then _streamPos shows real end of stream

    private var _pointerToLastSafePosition:Int;
    
    public var _bufferOffset:Int;
    
    public var _blockSize:Int; // Size of Allocated memory block
    public var _pos:Int; // offset (from _buffer) of curent byte
    private var _keepSizeBefore:Int; // how many BYTEs must be kept in buffer before _pos
    private var _keepSizeAfter:Int; // how many BYTEs must be kept buffer after _pos
    public var _streamPos:Int; // offset (from _buffer) of first not read byte from Stream
    
    public function new() {}
    
    public function moveBlock():Void {
        var offset:Int = _bufferOffset + _pos - _keepSizeBefore;
        // we need one additional byte, since MovePos moves on 1 byte.
        if (offset > 0) offset--;
        var numBytes:Int = _bufferOffset + _streamPos - offset;
        
        // check negative offset ????
        _bufferBase.blit(offset, _bufferBase, 0, numBytes);
        for (i in 0...numBytes)
			_bufferBase.set(i, _bufferBase.get(offset + i));
        _bufferOffset -= offset;
    }
    
    public function readBlock():Void {
		if (_streamEndWasReached) return;
		while (true) {
			var size:Int = (0 - _bufferOffset) + _blockSize - _streamPos;
			if (size == 0) return;
			var numReadBytes:Int;
			try {
				numReadBytes = _stream.readBytes(_bufferBase, _bufferOffset + _streamPos, size);
			} catch (e:Eof) {
				_posLimit = _streamPos;
				var pointerToPostion:Int = _bufferOffset + _posLimit;
				if (pointerToPostion > _pointerToLastSafePosition)
					_posLimit = _pointerToLastSafePosition - _bufferOffset;
					
				_streamEndWasReached = true;
				return;
			}
			_streamPos += numReadBytes;
			if (_streamPos >= _pos + _keepSizeAfter) _posLimit = _streamPos - _keepSizeAfter;
		}
	}

    public function free():Void _bufferBase = null; 
    
    public function Create(keepSizeBefore:Int, keepSizeAfter:Int, keepSizeReserv:Int):Void {
        _keepSizeBefore = keepSizeBefore;
        _keepSizeAfter = keepSizeAfter;
        var blockSize:Int = keepSizeBefore + keepSizeAfter + keepSizeReserv;
        if (_bufferBase == null || _blockSize != blockSize) {
            free();
            _blockSize = blockSize;
            _bufferBase = haxe.io.Bytes.alloc(_blockSize);
        }
        _pointerToLastSafePosition = _blockSize - keepSizeAfter;
    }
    
    public function setStream(stream:haxe.io.Input):Void { _stream = stream; }
    public function releaseStream():Void { _stream = null; }

    public function init():Void {
        _bufferOffset = 0;
        _pos = 0;
        _streamPos = 0;
        _streamEndWasReached = false;
        readBlock();
    }
    
    public function movePos():Void {
        _pos++;
        if (_pos > _posLimit) {
            var pointerToPostion:Int = _bufferOffset + _pos;
            if (pointerToPostion > _pointerToLastSafePosition) moveBlock();
            readBlock();
        }
    }
    
    public function getIndexByte(index:Int):Int { return _bufferBase.get(_bufferOffset + _pos + index); }
    
    // index + limit have not to exceed _keepSizeAfter;
    public function getMatchLen(index:Int, distance:Int, limit:Int):Int {
        if (_streamEndWasReached)
            if ((_pos + index) + limit > _streamPos) limit = _streamPos - (_pos + index);
        distance++;
        var pby:Int = _bufferOffset + _pos + index;
        
        var i:Int = 0;
        while (i < limit && _bufferBase.get(pby + i) == _bufferBase.get(pby + i - distance)) i++;
        return i;
    }
    
    public function getNumAvailableBytes():Int { return _streamPos - _pos; }
    
    public function reduceOffsets(subValue:Int):Void {
        _bufferOffset += subValue;
        _posLimit -= subValue;
        _pos -= subValue;
        _streamPos -= subValue;
    }
}
