package sevenZip.compression.lzma;

import sevenZip.compression.lz.OutWindow;
import sevenZip.compression.rangeCoder.BitTreeDecoder;
import sevenZip.compression.rangeCoder.Decoder;
import haxe.Int64;

class Decoder {
	public function new() {}
	
    var m_OutWindow:OutWindow = new OutWindow();
    var m_RangeDecoder:sevenZip.compression.rangeCoder.Decoder = new sevenZip.compression.rangeCoder.Decoder();
    
    var m_IsMatchDecoders:Array<Int>;
    var m_IsRepDecoders:Array<Int>;
    var m_IsRepG0Decoders:Array<Int>;
    var m_IsRepG1Decoders:Array<Int>;
    var m_IsRepG2Decoders:Array<Int>;
    var m_IsRep0LongDecoders:Array<Int>;
    
    var m_PosSlotDecoder:Array<BitTreeDecoder>;
    var m_PosDecoders:Array<Int>;
    
    var m_PosAlignDecoder:BitTreeDecoder = new BitTreeDecoder(Base.kNumAlignBits);
    
    var m_LenDecoder:LenDecoder = new LenDecoder();
    var m_RepLenDecoder:LenDecoder = new LenDecoder();
    
    var m_LiteralDecoder:LiteralDecoder = new LiteralDecoder();
    
    var m_DictionarySize:Int;
    var m_DictionarySizeCheck:Int;
    
    var m_PosStateMask:Int;
    
    public function decoder() {
        m_IsMatchDecoders = [];
        m_IsRepDecoders = [];
        m_IsRepG0Decoders = [];
        m_IsRepG1Decoders = [];
        m_IsRepG2Decoders = [];
        m_IsRep0LongDecoders = [];
        for (i in 0...(Base.kNumStates << Base.kNumPosStatesBitsMax)) {
            m_IsMatchDecoders.push(0);
        }
        for (i in 0...Base.kNumStates) {
            m_IsRepDecoders.push(0);
            m_IsRepG0Decoders.push(0);
            m_IsRepG1Decoders.push(0);
            m_IsRepG2Decoders.push(0);
        }
        for (i in 0...(Base.kNumStates << Base.kNumPosStatesBitsMax)) {
            m_IsRep0LongDecoders.push(0);
        }
        
        m_PosSlotDecoder = [];
        for (i in 0...Base.kNumLenToPosStates) {
            m_PosSlotDecoder.push(new BitTreeDecoder(Base.kNumPosSlotBits));
        }
        
        m_PosDecoders = [];
        for (i in 0...(Base.kNumFullDistances - Base.kEndPosModelIndex)) {
            m_PosDecoders.push(0);
        }
    }
    
    public function setDictionarySize(dictionarySize:Int):Bool {
        if (dictionarySize < 0) return false;
        if (m_DictionarySize != dictionarySize) {
            m_DictionarySize = dictionarySize;
            m_DictionarySizeCheck = Std.int(Math.max(m_DictionarySize, 1));
            m_OutWindow.create(Std.int(Math.max(m_DictionarySizeCheck, (1 << 12))));
        }
        return true;
    }
    
    public function setLcLpPb(lc:Int, lp:Int, pb:Int):Bool {
        if (lc > Base.kNumLitContextBitsMax || lp > 4 || pb > Base.kNumPosStatesBitsMax) return false;
        m_LiteralDecoder.create(lp, lc);
        var numPosStates:Int = 1 << pb;
        m_LenDecoder.create(numPosStates);
        m_RepLenDecoder.create(numPosStates);
        m_PosStateMask = numPosStates - 1;
        return true;
    }
    
    public function init():Void {
        m_OutWindow.init(false);
        
		decoder();
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsMatchDecoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsRep0LongDecoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsRepDecoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsRepG0Decoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsRepG1Decoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_IsRepG2Decoders);
        sevenZip.compression.rangeCoder.Decoder.initBitModels(m_PosDecoders);
        
        m_LiteralDecoder.init();

        for (i in 0...Base.kNumLenToPosStates) {
            m_PosSlotDecoder[i].init();
        }
        m_LenDecoder.init();
        m_RepLenDecoder.init();
        m_PosAlignDecoder.init();
        m_RangeDecoder.init();
    }
	
	public function code(inStream:haxe.io.Input, outStream:haxe.io.Output, outSize:Int):Bool {
		m_RangeDecoder.setStream(inStream);
		m_OutWindow.setStream(outStream);
		init();
		
		var state:Int = Base.stateInit();
		var rep0:Int = 0, rep1:Int = 0, rep2:Int = 0, rep3:Int = 0;
		
		var nowPos64:Int64 = 0;
		var prevByte = 0;
		while (outSize < 0 || nowPos64.low < outSize) {
			var posState:Int = nowPos64.low & m_PosStateMask;
			if (m_RangeDecoder.decodeBit(m_IsMatchDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
				var decoder2:Decoder2 = m_LiteralDecoder.getDecoder(nowPos64.low, prevByte);
				if (!Base.stateIsCharState(state))
					prevByte = decoder2.decodeWithMatchByte(m_RangeDecoder, m_OutWindow.getByte(rep0));
				else
					prevByte = decoder2.decodeNormal(m_RangeDecoder);
				m_OutWindow.putByte(prevByte);
				state = Base.stateUpdateChar(state);
				nowPos64++;
			} else {
				var len:Int;
				if (m_RangeDecoder.decodeBit(m_IsRepDecoders, state) == 1) {
					len = 0;
					if (m_RangeDecoder.decodeBit(m_IsRepG0Decoders, state) == 0) {
						if (m_RangeDecoder.decodeBit(m_IsRep0LongDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
							state = Base.stateUpdateShortRep(state);
							len = 1;
						}
					} else {
						var distance:Int;
						if (m_RangeDecoder.decodeBit(m_IsRepG1Decoders, state) == 0)
							distance = rep1;
						else {
							if (m_RangeDecoder.decodeBit(m_IsRepG2Decoders, state) == 0)
								distance = rep2;
							else {
								distance = rep3;
								rep3 = rep2;
							}
							rep2 = rep1;
						}
						rep1 = rep0;
						rep0 = distance;
					}
					if (len == 0) {
						len = m_RepLenDecoder.decode(m_RangeDecoder, posState) + Base.kMatchMinLen;
						state = Base.stateUpdateRep(state);
					}
				} else {
					rep3 = rep2;
					rep2 = rep1;
					rep1 = rep0;
					len = Base.kMatchMinLen + m_LenDecoder.decode(m_RangeDecoder, posState);
					state = Base.stateUpdateMatch(state);
					var posSlot:Int = m_PosSlotDecoder[Base.getLenToPosState(len)].decode(m_RangeDecoder);
					if (posSlot >= Base.kStartPosModelIndex) {
						var numDirectBits:Int = (posSlot >> 1) - 1;
						rep0 = ((2 | (posSlot & 1)) << numDirectBits);
						if (posSlot < Base.kEndPosModelIndex)
							rep0 += BitTreeDecoder._reverseDecode(m_PosDecoders,
									rep0 - posSlot - 1, m_RangeDecoder, numDirectBits);
						else {
							rep0 += (m_RangeDecoder.decodeDirectBits(
									numDirectBits - Base.kNumAlignBits) << Base.kNumAlignBits);
							rep0 += m_PosAlignDecoder.reverseDecode(m_RangeDecoder);
							if (rep0 < 0) {
								if (rep0 == -1)
									break;
								return false;
							}
						}
					} else
						rep0 = posSlot;
				}
				if (rep0 >= nowPos64 || rep0 >= m_DictionarySizeCheck) {
					// m_OutWindow.flush();
					return false;
				}
				m_OutWindow.copyBlock(rep0, len);
				nowPos64 += len;
				prevByte = m_OutWindow.getByte(0);
			}
		}
		m_OutWindow.flush();
		m_OutWindow.releaseStream();
		m_RangeDecoder.releaseStream();
		return true;
	}

	public function setDecoderProperties(properties:haxe.io.Bytes):Bool {
		if (properties.length < 5)
			return false;
		var val:Int = properties.get(0) & 0xFF;
		var lc:Int = val % 9;
		var remainder:Int = Std.int(val / 9);
		var lp:Int = Std.int(remainder % 5);
		var pb:Int = Std.int(remainder / 5);
		var dictionarySize:Int = 0;
		for (i in 0...4)
			dictionarySize += (properties.get(i + 1) & 0xFF) << (i * 8);
		if (!setLcLpPb(lc, lp, pb))
			return false;
		return setDictionarySize(dictionarySize);
	}

}

private class LenDecoder {
    var m_Choice:Array<Int> = [0, 0];
    var m_LowCoder:Array<BitTreeDecoder> = [];
    var m_MidCoder:Array<BitTreeDecoder> = [];
    var m_HighCoder:BitTreeDecoder;
    var m_NumPosStates:Int = 0;
	
	public function new() {}
    
    public function create(numPosStates:Int):Void {
        for ( posState in 0...numPosStates) {
            m_LowCoder.push(new BitTreeDecoder(Base.kNumLowLenBits));
            m_MidCoder.push(new BitTreeDecoder(Base.kNumMidLenBits));
            m_NumPosStates++;
        }
        m_HighCoder = new BitTreeDecoder(Base.kNumHighLenBits);
    }
    
    public function init():Void {
		sevenZip.compression.rangeCoder.Decoder.initBitModels(m_Choice);
		for ( posState in 0...m_NumPosStates) {
			m_LowCoder[posState].init();
			m_MidCoder[posState].init();
		}
		m_HighCoder.init();
	}

    
    public function decode(rangeDecoder:sevenZip.compression.rangeCoder.Decoder, posState:Int):Int {
        if (rangeDecoder.decodeBit(m_Choice, 0) == 0)
            return m_LowCoder[posState].decode(rangeDecoder);
        var symbol:Int = Base.kNumLowLenSymbols;
        if (rangeDecoder.decodeBit(m_Choice, 1) == 0)
            symbol += m_MidCoder[posState].decode(rangeDecoder);
        else
            symbol += Base.kNumMidLenSymbols + m_HighCoder.decode(rangeDecoder);
        return symbol;
    }
}

private class LiteralDecoder {
    var m_Coders:Array<Decoder2>;
    var m_NumPrevBits:Int;
    var m_NumPosBits:Int;
    var m_PosMask:Int;
	
	public function new() {}
    
    public function create(numPosBits:Int, numPrevBits:Int):Void {
        if (m_Coders != null && m_NumPrevBits == numPrevBits && m_NumPosBits == numPosBits) return;
        m_NumPosBits = numPosBits;
        m_PosMask = (1 << numPosBits) - 1;
        m_NumPrevBits = numPrevBits;
        var numStates:Int = 1 << (m_NumPrevBits + m_NumPosBits);
        m_Coders = [];
        for (i in 0...numStates) m_Coders.push(new Decoder2());
    }
    
    public function init():Void {
        var numStates:Int = 1 << (m_NumPrevBits + m_NumPosBits);
        for (i in 0...numStates) m_Coders[i].init();
    }
    
    public function getDecoder(pos:Int, prevByte:Int):Decoder2 {
        return m_Coders[((pos & m_PosMask) << m_NumPrevBits) + ((prevByte & 0xFF) >>> (8 - m_NumPrevBits))];
    }
}
private class Decoder2 {
	var m_Decoders:Array<Int>;
	
	public function new() {
		m_Decoders = [];
		for (i in 0...0x300) m_Decoders.push(0);
	}
	
	public function init():Void {
		sevenZip.compression.rangeCoder.Decoder.initBitModels(m_Decoders);
	}
	
	public function decodeNormal(rangeDecoder:sevenZip.compression.rangeCoder.Decoder):Int {
		var symbol:Int = 1;
		while (symbol < 0x100) {
			symbol = (symbol << 1) | rangeDecoder.decodeBit(m_Decoders, symbol);
		}
		return symbol;
	}
	
	public function decodeWithMatchByte(rangeDecoder:sevenZip.compression.rangeCoder.Decoder, matchByte:Int):Int {
		var symbol:Int = 1;
		while (symbol < 0x100) {
			var matchBit:Int = (matchByte >> 7) & 1;
			matchByte <<= 1;
			var bit:Int = rangeDecoder.decodeBit(m_Decoders, ((1 + matchBit) << 8) + symbol);
			symbol = (symbol << 1) | bit;
			if (matchBit != bit) {
				while (symbol < 0x100) {
					symbol = (symbol << 1) | rangeDecoder.decodeBit(m_Decoders, symbol);
				}
				break;
			}
		}
		return symbol;
	}
}