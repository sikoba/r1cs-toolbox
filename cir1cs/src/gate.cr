
require "big.cr"
require "json"
require "./utils.cr"
require "./jr1cs.cr"
require "./circuit_parser.cr"

module Cir1cs

    

class LinearCombination
    def initialize
        @lc = Array(Tuple(UInt32,BigInt)).new
       
    end

    def initialize(lc : Array(Tuple(UInt32,BigInt)))
        @lc = lc;
    end

    def add(lc : LinearCombination, prime : BigInt)
        add(lc.@lc, prime)
    end

    def add(lc : Array(Tuple(UInt32,BigInt)), prime : BigInt)
        #WARNING - We suppose both are ordered!
        result = Array(Tuple(UInt32,BigInt)).new
        i1 = 0; 
        i2 = 0
        while (i1 < @lc.size && i2 < lc.size)
            if (@lc[i1][0] < lc[i2][0])
                result << @lc[i1]
                i1 +=1;
            elsif((@lc[i1][0] > lc[i2][0]))
                result << lc[i2]
                i2 +=1;
            else
                #addition
                @lc[i1] = {lc[i2][0], (lc[i2][1] + @lc[i1][1]).modulo(prime)};       ##I don't know how to update only lc[i2][1]..
                result << @lc[i1]
                i2 +=1;
                i1 +=1;
            end
        end
        while (i1 < @lc.size)
            result << @lc[i1]
            i1 +=1;
        end
        while (i2 < lc.size)
            result << lc[i2]
            i2 +=1;
        end
        @lc = result;
    end

    def multiply(scalar : BigInt, prime : BigInt)
        newlc = Array(Tuple(UInt32,BigInt)).new
        @lc.each do |item|
            newlc << {item[0], (item[1] * scalar).modulo(prime)}; #
        end
        @lc = newlc ##should update @lc in-place!
    end

    def multiply_lc(lc : Array(Tuple(UInt32,BigInt)), scalar : BigInt, prime : BigInt)
        lc.each do |item|
            @lc << {item[0], (item[1] * scalar).modulo(prime)};
        end
    end
end

class InternalVar
    @val : BigInt;
    @expression : LinearCombination;
    @witness_idx : UInt32 | Nil;
    property witness_idx : UInt32 | Nil;

    def initialize
        @val = BigInt.new(0);
        @expression = LinearCombination.new();
        @witness_idx = nil;
    end

    def initialize(expression, value, widx : UInt32| Nil)
        @val = value;
        @expression = expression;
        @witness_idx = widx;
    end

end


class GateKeeper

    @prime_field : BigInt;

    def initialize(@arithName : String, @j1csName : String, internals : Hash(UInt32,InternalVar))
        @r1csFile =  File.new(j1csName, "w");
        @internalCache = internals;
        @witness_idx = Array(UInt32).new();     ##TODO this structure will become too big, but we probably can keep only the last elements, as with internalCache.    witness_idx[i] = w means that wire w has index i (correspond to variable xi in the r1cs)
        @inputs_nb = 0_u32;
        @nzik_nb = 0_u32;
        @output_nb = 0_u32;
        @constraint_nb = 0;
        @witness_nb = 0;
        #@prime_field  = BigInt.new(2)**252 + BigInt.new("27742317777372353535851937790883648493")  ##Bullet proof #TODO; custom
        @prime_field  = BigInt.new("21888242871839275222246405745257275088548364400416034343698204186575808495617")  ##libsnark bn128
        @cur_idx = 0_u32;
        
        @j1cs = nil;
        @previous_stage = 0;        ##Stage of the circuit parsing
    end

    def log_me(l : SimpleLog)
        @log = l;
    end
    ##TODO DEPRECATED
    #def setInputs(public_inputs : UInt32, private_inputs : UInt32)
    #    @inputs_nb = public_inputs
    #    @nzik_nb = private_inputs
    #    load_inputs("ex1.ari") #TODO TEMP
    #end

    def writeToJ1CS(str : String)
        #JSON.parse(str).to_json(@r1csFile)
        #@r1csFile.print("\n")
        @r1csFile.print("#{str}\n")
    end

    def write_assignements
        str = inputs_to_json();
        ff = File.new("#{@j1csName}.in", "w");   
        ff.print("#{str}")
        ff.close();
    end

    ##TODO 
    def read_ari_input_values (source_filename) : Array(BigInt)
        filename = "#{source_filename}.in"
        values = [] of BigInt
        if File.exists?(filename)
            File.each_line(filename) do |line|
                str_val = line.split
                #if str_val.size() != 2 ERROR
                values << str_val[1].to_u64(16).to_big_i 
            end
        end
        return values
    end

    def process_circuit
        first_pass();
        main_pass();
    end

    def first_pass
        cp = CircuitParser.new();
        if (@log)
            cp.enable_log(@log);
        end

        in_values = read_ari_input_values(@arithName) #load inputs from .ari.in file

        cp.set_callback(:input_wire, ->(s : Int32, w : UInt32) 
        {
            @internalCache[w] = InternalVar.new(LinearCombination.new([{w, BigInt.new(1)}]), in_values[w],(w+1).to_u32);  
            @inputs_nb += 1
            return
        })
        cp.set_callback(:nzikinput_wire, ->(s : Int32, w : UInt32)  
        {
        
            @nzik_nb += 1
            return
        })
        cp.set_callback(:out_wire, ->(s : Int32, w : UInt32) 
        {
            #map output wire and its r1cs index
            @internalCache[w] = InternalVar.new(LinearCombination.new([{w, BigInt.new(1)}]), BigInt.new(0), @inputs_nb + @output_nb);
            @output_nb += 1;
            return
        })


        cp.set_callback(:mul, ->(s : Int32, i : Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += 1;
            @witness_nb += 1;
            return;
        });

        cp.set_callback(:split, ->(s : Int32, i:  Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += o.size() + 1;
            @witness_nb += o.size();
            return;
        });
        cp.set_callback(:zerop, ->(s : Int32, i : Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += 2;
            @witness_nb += 2;
            return;
        });
    
        cp.parse_arithmetic_circuit(@arithName)
        @internalCache[@inputs_nb-1] = InternalVar.new(LinearCombination.new([{@inputs_nb-1, BigInt.new(1)}]), BigInt.new(1), 0_u32);       #One Constant

        #nzik inputs must be set after the ouputs
        (@inputs_nb..@inputs_nb+@nzik_nb-1).each do |i|
            @internalCache[i] = InternalVar.new(LinearCombination.new([{i.to_u32, BigInt.new(1)}]), in_values[i],(i+@output_nb).to_u32);     
        end
        @witness_nb = @witness_nb - @output_nb;
        @cur_idx = @inputs_nb+@nzik_nb+@output_nb;          
    end

    def main_pass
        pp "translating constraints"
        @stage = 0;
        ##load_inputs(@arithName);
        header = j1cs_helper().json_header(@constraint_nb, @prime_field, @inputs_nb-1+ @output_nb, @witness_nb)    
        writeToJ1CS(header)    #Write the r1cs header in the file
        cp = CircuitParser.new();
        cp.enable_log(@log);

        cp.set_callback(:add, ->add(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:mul, ->mul(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:const_mul, ->constMul(Int32, BigInt, Array(UInt32),  Array(UInt32)));
        cp.set_callback(:const_mul_neg, ->constMulNeg(Int32,  BigInt, Array(UInt32),  Array(UInt32)));
        cp.set_callback(:split, ->split(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:zerop, ->zerop(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:done, ->
        {
            @r1csFile.close();
            write_assignements();
            return;
        })
        cp.parse_arithmetic_circuit(@arithName)
        if @cur_idx-@inputs_nb-@output_nb != @witness_nb
            pp "WARNING - inconsistent witness value #{@cur_idx-@inputs_nb-@output_nb}"
        end
    end



    def set_witness(wire : UInt32, val : BigInt, check = false)
        #we check for an existing wire only when 'check' is true, may be this optimization is not worth, the idea is only outputs should already be in the cache and outputs should come from a mul gate
        #it would be also better to check only when the wire is greater than the first output...TODO
        if (check)
            v = @internalCache[wire]?
            if (v)
                var_idx = @internalCache[wire].@witness_idx
                @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, var_idx);       #why can't we simply update elements of an hash_map?
                return;
            end
        end
        @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, @cur_idx);
        @cur_idx += 1;

       # if wire < @out_wire    
       #     @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, @cur_idx);
       #     @cur_idx += 1;
       # else
       #     var_idx = @internalCache[wire].@witness_idx
       #     @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, var_idx);
       # end
    end

    def j1cs_helper
        if (!@j1cs)
            @j1cs = J1CS.new(self)      #cannot initialize it in the constructor
        end
        return @j1cs.not_nil!
    end

    def resetIdx
        @cur_idx = @inputs_nb
    end

    #TODO to change if we support negative indexes
    #This function returns the witness index (in the R1CS) corresponding to the wire (in the circuit)
    #Cf. wire mappings in the documentation -TODO
    def getWireIdx(wire : UInt32) : UInt32  
        if @internalCache.has_key? wire
            if w = @internalCache[wire].@witness_idx
                return w
            end
        end

        raise Exception.new("wire #{wire} not found"); 
    end

    #When a gate does not generate a multiplication, the output wires of the gate can be expressed as a linear combination of the inputs. In that case, each time such wire will be used, we can subtitute it with the linear combination.
    #This function stores the substitution in the cache
    def substitute(wire : UInt32)
        if @internalCache.has_key? wire
            return @internalCache[wire];
        end
        pp "n.b: wire #{wire} not found in the cache"
        lc = LinearCombination.new([{wire, BigInt.new(1)}]);
        return InternalVar.new(lc, BigInt.new(0), nil);
    end

    #Returns the wire representing the one-constant (for Pinocchio circuits). It should be mapped to variable x0
    def one_constant
        return  [{@inputs_nb-1, BigInt.new(1)}]
    end

    def scalar(c : Int32)
        if (c >= 0)
            return  {@inputs_nb-1, BigInt.new(c).modulo(@prime_field)}
        else
            return  {@inputs_nb-1,BigInt.new(c).modulo(@prime_field)} #c+@prime_filed
        end

    end

    ## construct the json string of the R1CS inputs and witnesses, from the cache
    def inputs_to_json()
        
        inputs = Array(String).new
        witnesses = Array(String).new
        @internalCache.each_value do |var|
            if (w = var.@witness_idx) 
                if w>0
                    if (w< @inputs_nb+@nzik_nb+@output_nb )
                        inputs << var.@val.to_s
                        #pp "input_#{w} idx:#{var.@witness_idx} value: #{var.@val}"
                    else
                        witnesses << var.@val.to_s
                        #pp "witnesses_#{w} idx:#{var.@witness_idx} value: #{var.@val}"
                    end
                end
            end
        end
       
        return  @j1cs.not_nil!.inputs_to_json(inputs,witnesses);
        
    end


    #Addition gate
    def add(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        lc = LinearCombination.new();
        val = BigInt.new(0);
        in_wires.each do |wire|
            cache = substitute(wire)
           
            lc.add(cache.@expression, @prime_field);
    
            val = (val+cache.@val).modulo(@prime_field);
        end
        @internalCache[out_wires[0]] =  InternalVar.new(lc, val.modulo(@prime_field), nil); 
        #DEBUG:
        #if (evaluate(lc.@lc) != val)
        #    pp "addition error for wirea #{in_wires} - found #{evaluate(lc.@lc)} but computed #{val}"
        #end
        return;
    end

    ## Multiplication gate
    def mul(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        #We suppose there are only 2 input wires
        cache1 = substitute(in_wires[0])
        cache2 = substitute(in_wires[1])
        val = cache1.@val * cache2.@val;      
        set_witness(out_wires[0], val.modulo(@prime_field), true)
        str_res = @j1cs.not_nil!.to_json_str(cache1.@expression.@lc, cache2.@expression.@lc,  [{out_wires[0], BigInt.new(1)}])
        #DEBUG:  satisfy(cache1.@expression.@lc, cache2.@expression.@lc,  [{out_wires[0], BigInt.new(1)}])
        writeToJ1CS(str_res);   
        return;
    end

    def constMul(s : Int32, scalar : BigInt, in_wires : Array, out_wires : Array)
        @stage = s;
        cache = substitute(in_wires[0]);
        llc = LinearCombination.new();
        llc.multiply_lc(cache.@expression.@lc, scalar, @prime_field);
      
        @internalCache[out_wires[0]] = InternalVar.new(llc,  (scalar*cache.@val).modulo(@prime_field), nil);
        #DEBUG
        #if (evaluate(llc.@lc) != (scalar*cache.@val).modulo(@prime_field))
        #    pp "const-mul-.. error for wire #{in_wires}"
        #end
        return;
    end

    def constMulNeg(s : Int32, scalar : BigInt, in_wires : Array, out_wires : Array)
        return constMul(s, -scalar, in_wires, out_wires)
    end

    def zerop(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        cache = substitute(in_wires[0]);
        ##compute outputs
        val0, val1 =  BigInt.new(0),  BigInt.new(0);
        if (cache.@val != BigInt.new(0))
            val1 = BigInt.new(1);     
            val0 = Maths.new().exp_modulo(cache.@val, @prime_field-2, @prime_field);     #TODO   anybetter inverse?  #static method??
        end
        set_witness(out_wires[0], val0);
        set_witness(out_wires[1], val1)

        str_res = j1cs_helper().to_json_str(cache.@expression.@lc, [{ out_wires[1], BigInt.new(1)}], cache.@expression.@lc)
        writeToJ1CS(str_res);  

        str_res = j1cs_helper().to_json_str(cache.@expression.@lc, [{ out_wires[0], BigInt.new(1)}], [{ out_wires[1], BigInt.new(1)}])
        satisfy(cache.@expression.@lc, [{ out_wires[0], BigInt.new(1)}], [{ out_wires[1], BigInt.new(1)}])
        writeToJ1CS(str_res);  
        return;
    end

    
    def split(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        a_lc = Array(Tuple(UInt32, BigInt)).new;
        s = out_wires.size;
        e = BigInt.new(1);
        (0..s-1).each do |i|
            a_lc << {out_wires[i], e}
            e = e * 2;
        end
        cache = substitute(in_wires[0])
        #compute outputs
         (0..s-1).each do |i|
            set_witness(out_wires[i], cache.@val.bit(i).to_big_i)
         end       
        
        (0..s-1).each do |i| 
            str_res = j1cs_helper().to_json_str([{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}])
            #str_res = j1cs_helper().to_json_str([{out_wires[i], BigInt.new(1)}], [ scalar(-1), {out_wires[i], BigInt.new(1)}], [scalar(0)])        ##libsnark style
            #DEBUG satisfy([{out_wires[i], BigInt.new(1)}], [ scalar(-1), {out_wires[i], BigInt.new(1)}], [scalar(0)])   
            writeToJ1CS(str_res);
        end
        str_res = j1cs_helper().to_json_str(a_lc, one_constant, cache.@expression.@lc)
        #str_res = j1cs_helper().to_json_str(cache.@expression.@lc, one_constant, a_lc)                       ##libsnark style
        #DEBUG satisfy(cache.@expression.@lc, one_constant, a_lc))
        writeToJ1CS(str_res);  
        
        return;
    end

    def join(in_wires : Array, out_wires : Array)
        a_lc = LinearCombination.new;
        s = in_wires.size;
        e = BigInt.new(1);
        val = BigInt.new(0);
        (0..s-1).each do |i|
            cache = substitute(in_wires[i])
            a_lc.add(cache.@expression.multiply(e));
            val += e*cache.@val
            e = e * 2;
        end
        set_witness(out_wires[0], val.modulo(@prime_field))
        str_res = j1cs_helper().to_json_str(a_lc.@lc, [{@inputs_nb-1, BigInt.new(1)}], [{out_wires[0],  BigInt.new(1)}])
        writeToJ1CS(str_res);
    end

    ########################################
    ### DEBUG helpers ######################
    def evaluate(lc : Array(Tuple(UInt32,BigInt)))
        result = BigInt.new(0);
        lc.each do |item|
            result += substitute(item[0]).@val * item[1];
        end
        return result.modulo(@prime_field);
    end

    def satisfy(a : Array(Tuple(UInt32,BigInt)), b : Array(Tuple(UInt32,BigInt)),  c : Array(Tuple(UInt32,BigInt)))
        if ( (evaluate(a)*evaluate(b)-evaluate(c)).modulo(@prime_field) == BigInt.new(0) )
            return true
        end
        pp "NOT SATIISFIED!!"
        return false;
    end
end


end