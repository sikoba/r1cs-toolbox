require "./utils.cr"
require "./gate.cr"

module Cir1cs

  VERSION = "0.1.0"

  # initialise logger

  @@sl = SimpleLog.new({
    :caller => "#{__FILE__}",
    :flogs => "./cir1cs.log",
    :fwarn => "./cir1cs.warn.log",
    :verbose => "1"
  })

  # inputs

  acpath = ARGV[0]
  @@sl.header "Reading file #{acpath}"
  @@sl.abort "file #{acpath} not found" if !File.file? acpath
  
  # initialise circuit variables

  inputs = Array(Int32).new
  nizkinputs = Array(Int32).new
  ops = Array( Array(Int32 | Array(Int32) | Symbol) ).new
  output = 0
  
  @@wires = Array(Int32).new
  
  # wires tracking

  def self.add_input_wires(inputs : Array(Int32))
    inputs.each do |iw|
	  @@sl.abort "input wire #{iw} already present" if @@wires.includes?(iw)
	  @@wires << iw
	end
  end
  
  def self.add_wires(inputs : Array(Int32), outputs : Array(Int32))
    inputs.each do |iw|
	  @@sl.abort "input wire #{iw} not found" unless @@wires.includes?(iw)
	end
    outputs.sort.each do |ow|
	  @@sl.abort "output wire #{ow} already present" if @@wires.includes?(ow)
	  @@sl.abort "a new wire number (#{ow}) should be exactly one more than the previous highest wire number (#{@@wires[-1]})" if @@wires[-1] + 1 != ow
	  @@wires << ow
	end
  end
  
  begin
    #parse_arithmetic_circuit(acpath, inputs, nizkinputs, output, ops)
    rootName = acpath
    if acpath =~ /^(.+)\..+$/
      rootName = $1      
    end
    gates : GateKeeper = GateKeeper.new(acpath, "#{rootName}.j1",  Hash(UInt32,InternalVar).new)
    #gates.log_me(@@sl);
    gates.process_circuit;
  rescue ex
    @@sl.abort ex.message
  end




  #############################################################################
  #
  # parse input file
  #
  
  # this input file has the structure
  #
  # total (1 line)
  # input
  # nizkinput
  # operations (currently: add mul const-mul-xx const-mul-neg-xx zerop split)
  # output (1 line)
  
  def self.parse_arithmetic_circuit(file_path, inputs, nizkinputs, output, ops)
    stage = 0
    line_count = 0 # count of line_count in input file
    circuit_line_count = 0 # declared line count in first line
    
    gates : GateKeeper = GateKeeper.new("monr1cs.txt",  Hash(UInt32,InternalVar).new)
    ########TOTO plug the input parsing to the gates
    ########### + also generate the r1cs.in and compute the assignements
    File.each_line file_path do |line|
      
    line_count += 1
     @@sl.p "\n** processing line #{line_count} [#{line}]\n"
    line = line.gsub(/\s*#.*$/, "")
      
     ### total
      
    if line =~ /^total (\d+)$/
        
      @@sl.abort "expecting total on first line" if stage > 0
      stage = 1
        
      circuit_line_count = $1.to_i
  
      @@sl.p "   total circuit line_count expected: #{circuit_line_count}"
      
      ### input
  
    elsif line =~ /^input (\d+)$/
  
      @@sl.abort "Unexpected input on this line" if stage != 1
        
      inputs << $1.to_i
  
      add_input_wires([$1.to_i])
      
      @@sl.p "   added input wire #{$1.to_i}"
  
      ### nizkinputs
      
    elsif line =~ /^nizkinput (\d+)$/
        
      @@sl.abort "Unexpected nizkinput on this line" if stage != 1
        
       nizkinputs << $1.to_i
  
       add_input_wires([$1.to_i])
      
      @@sl.p "   added nizkinput wire #{$1.to_i}"
  
      ### output
        
    elsif line =~ /^output (\d+)$/
  
      @@sl.abort "Unexpected output on this line" unless [2, 3].includes?(stage)

      if (stage == 2)
        gates.resetIdx()
      end
      stage = 3
      
      output = $1.to_i
      
     # add_wires([] of Int32, [$1.to_i])
    #  gates.setOutput($1.to_u32)
      
      @@sl.p "   added output wire #{$1.to_i}"
      
    else    
  
      ### gates
      
      @@sl.abort "Unexpected gate on this line" unless [1, 2].includes?(stage)
  
      if (stage == 1 )
        gates.setInputs(inputs.size.to_u32, nizkinputs.size.to_u32)
      end
  
      stage = 2    
  
      # add
  
      if line =~ /^add in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
    
        a = Array(Int32).new
        ua = Array(UInt32).new
        a = $2.split.map{ |x| x.to_i }
        ua = $2.split.map{ |x| x.to_u32 }
        abort "Inconsistent number of inputs:  #{line} " if a.size != $1.to_i
        ops << [ :add, a, $3.to_i ]
     
        add_wires(a, [$3.to_i])
        gates.add(ua, [$3.to_u32])
  
      @@sl.p "   add #{a} = #{$3.to_i}"
  
        # mul
        
      elsif line =~ /^mul in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
        
        a = Array(Int32).new
        a = $2.split.map{ |x| x.to_i }
        ua = Array(UInt32).new
        ua = $2.split.map{ |x| x.to_u32 }
        abort "Inconsistent number of inputs:  #{line} " if a.size != $1.to_i      
        ops << [ :mul, a, $3.to_i ]
      
        add_wires(a, [$3.to_i])
        gates.mul(ua, [$3.to_u32])
  
      @@sl.p "   mul #{a} = #{$3.to_i}"
        
        # const-mul-neg-xx
        
      elsif line =~ /^const-mul-neg-(\d+) in 1 <(\d+)> out 1 <(\d+)>$/
  
        ops << [ :const_mul_neg, $1.to_i, $2.to_i, $3.to_i ]
      
      @@sl.p "   const_mul_neg -#{$1.to_i}_C x #{$2.to_i} = #{$3.to_i}"
      
        add_wires([$2.to_i], [$3.to_i])
        gates.constMulNeg($1.to_u32, [$2.to_u32], [$3.to_u32])
        
        # const-mul-xx
        
      elsif line =~ /^const-mul-([\dA-Fa-f]+) in 1 <(\d+)> out 1 <(\d+)>$/
        c = $1.to_u32(16)
        ops << [ :const_mul, c.to_i, $2.to_i, $3.to_i ]
      
      @@sl.p "   const_mul #{c}_C x #{$2.to_i} = #{$3.to_i}"
      
        add_wires([$2.to_i], [$3.to_i])
        gates.constMul(BigInt.new(c), [$2.to_u32], [$3.to_u32])
  
        # split
        
      elsif line =~ /^split in 1 <(\d+)> out (\d+) <([\s\d]+)>$/
        a = Array(Int32).new
        a = $3.split.map{ |x| x.to_i }
        ua = Array(UInt32).new
        ua = $3.split.map{ |x| x.to_u32 }
        abort "Inconsistent number of wires:  #{line} " if a.size != $2.to_i
        ops << [ :split, $1.to_i, a ]
      
      @@sl.p "   split #{$1.to_i} => #{a}"
      
        add_wires([$1.to_i], a)
        gates.split([$1.to_u32], ua)
  
        # zerop
        
      elsif line =~ /^zerop in 1 <(\d+)> out (\d+) <([\s\d]+)>$/
  
        a = Array(Int32).new
        a = $3.split.map{ |x| x.to_i }
        ua = Array(UInt32).new
        ua = $3.split.map{ |x| x.to_u32 }
        abort "Inconsistent number of outputs:  #{line} " if a.size != $2.to_i
        ops << [ :zerop, $1.to_i, a ]
      
      @@sl.p "   zerop #{$1.to_i} => #{a}"
  
        add_wires([$1.to_i], a)
        gates.zerop([$1.to_u32], ua)
        # unknown gate #
    
      else
        ###TODO       JOIN ###############
        ops << [ :imlost ]
      
        @@sl.p "unknown operation"
      
      end
    
    end
        
  end   ##file.each
    
  


    ## total is nulber of lines or number of wires?? @@sl.abort "Line number panic. Expected #{circuit_line_count}, found #{line_count - 1} " if circuit_line_count != line_count - 1
    
    gates.close()
  
  
    # get one-input
    
    oneinput = inputs.pop
  
    # print report of artitmetic circuit import
    
    @@sl.section "Result of arithemtic circuit import"
  
    @@sl.p "inputs"
    @@sl.p inputs.inspect
    
    @@sl.p "\noneinput"
    @@sl.p oneinput.inspect
  
    @@sl.p "\nnizkinputs"
    @@sl.p nizkinputs.inspect
    
    @@sl.p "\nops"
    ops.each do |a|
      @@sl.p a.inspect
    end
  
    @@sl.p "\noutput"
    @@sl.p output.inspect
  
    @@sl.p "\nwires"
    @@sl.p @@wires.inspect
    
    @@sl.dump
  end

  

  
 
  
  
end