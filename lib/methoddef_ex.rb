require 'llvm'
# Define method type and name information not compatible with CRuby
include LLVM

module Transaction
end

module YARV2LLVM

class LLVM_Type
end

class LLVM_Struct<LLVM_Type
  def initialize(type, member)
    @type = type
    @index_symbol = {}
    @member = []
    member.each_with_index do |ele, n|
      if ele.is_a?(Array) then
        @member[n] = ele[0]
        @index_symbol[ele[1]] = n
      else
        @member[n] = ele
      end
    end
  end
  
  attr_accessor :type
  attr_accessor :member
  attr_accessor :index_symbol
end
  
class LLVM_Pointer<LLVM_Type
  def initialize(type, member)
    @type = type
    @member = member
  end
  
  attr_accessor :type
  attr_accessor :member
end

class LLVM_Array<LLVM_Type
  def initialize(type, member, size)
    @type = type
    @member = member
    @size = size
  end
  
  attr_accessor :type
  attr_accessor :member
  attr_accessor :size
end

class LLVM_Vector<LLVM_Array
end

class LLVM_Function<LLVM_Type
  include LLVMUtil

  def initialize(type, ret, arga)
    @type = type
    @ret_type = ret
    @arg_type = arga
  end
  
  attr_accessor :type
  attr_accessor :ret_type
  attr_accessor :arg_type

  def arg_type_raw
    @arg_type.map {|e| get_raw_llvm_type(e) }
  end
end

module MethodDefinition
  include LLVMUtil

  InlineMethod_YARV2LLVM = {
    :define_macro => {
      :inline_proc => 
        lambda {|para|
          info = para[:info]
          code = para[:code]
          ins = para[:ins]
          arg0 = para[:args][0]
          blk = ins[3]
          code.blockes.delete(ins[3][1])
          mname =  arg0[0].content

          iseq = VMLib::InstSeqTree.new(nil, blk[0])
          prog = YarvTranslatorToRuby.new(iseq, binding, []).to_ruby

          MethodDefinition::InlineMacro[mname] = {
            :body => prog
          }

          @expstack.push [RubyType.value, 
            lambda {|b, context|
              context.rc = 4.llvm
              context
          }]
        }
    },

    :get_interval_cycle => {
      :inline_proc =>
        lambda {|para|
          info = para[:info]
          rettype = RubyType.fixnum(info[3], "Return type of gen_interval_cycle")
          prevvalp = add_global_variable("interval_cycle", 
                                     Type::Int64Ty, 
                                     0.llvm(Type::Int64Ty))
          @expstack.push [rettype,
            lambda {|b, context|
              prevval = b.load(prevvalp)
              ftype = Type.function(Type::Int64Ty, [])
              fname = 'llvm.readcyclecounter'
              func = context.builder.external_function(fname, ftype)
              curval = b.call(func)
              diffval = b.sub(curval, prevval)
              rc = b.trunc(diffval, MACHINE_WORD)
              b.store(curval, prevvalp)
              context.rc = rc
              context
          }]
      }
    },

  }

  InlineMethod_LLVM = {
    :struct => {
      :inline_proc => lambda {|para|
        info = para[:info]
        tarr = para[:args][0]
        rtarr = tarr[0].content
        rtarr2 = rtarr.map {|e| get_raw_llvm_type(e)}

        struct = Type.pointer(Type.struct(rtarr2))
        struct0 = LLVM_Struct.new(struct, rtarr)
        mess = "return type of LLVM::struct"
        type = RubyType.value(info[3], mess, LLVM_Struct)
        type.type.content = struct0
        @expstack.push [type,
          lambda {|b, context|
            context.rc = struct0.llvm
            context
          }
        ]
      }
    },

    :pointer => {
      :inline_proc => lambda {|para|
        info = para[:info]
        tarr = para[:args][0]
        dstt = tarr[0].content
        ptr = Type.pointer(get_raw_llvm_type(dstt))
        ptr0 = LLVM_Pointer.new(ptr, dstt)
        mess = "return type of LLVM::pointer"
        type = RubyType.value(info[3], mess, LLVM_Pointer)
        type.type.content =ptr0
        @expstack.push [type,
          lambda {|b, context|
            context.rc = ptr0.llvm
            context
          }
        ]
      }
    },

    :array => {
      :inline_proc => lambda {|para|
        info = para[:info]
        tarr = para[:args][0]
        tsiz = para[:args][1]
        dstt = tarr[0].content
        sizt = tsiz[0].content
        arr = Type.array(sizt, dstt)
        arr0 = LLVM_Array.new(arr, dstt, sizt)
        mess = "return type of LLVM::array"
        type = RubyType.value(info[3], mess, LLVM_Array)
        type.type.content =arr0
        @expstack.push [type,
          lambda {|b, context|
            context.rc = arr0.llvm
            context
          }
        ]
      }
    },

    :vector => {
      :inline_proc => lambda {|para|
        info = para[:info]
        tarr = para[:args][0]
        tsiz = para[:args][1]
        dstt = tarr[0].content
        sizt = tsiz[0].content
        vec = Type.vector(sizt, dstt)
        vec0 = LLVM_Vector.new(vec, dstt, sizt)
        mess = "return type of LLVM::vector"
        type = RubyType.value(info[3], mess, LLVM_Vector)
        type.type.content =vec0
        @expstack.push [type,
          lambda {|b, context|
            context.rc = vec0.llvm
            context
          }
        ]
      }
    },

    :function => {
      :inline_proc => lambda {|para|
        info = para[:info]
        ret = para[:args][1]
        arga = para[:args][0]
        rett = get_raw_llvm_type(ret[0].content)
        argta = arga[0].content

        argta2 = argta.map {|e| get_raw_llvm_type(e)}

        func = Type.function(rett, argta2)
        funcobj = LLVM_Function.new(func, rett, argta)
        mess = "return type of LLVM_Function"
        type = RubyType.value(info[3], mess, LLVM_Function)
        type.type.content = funcobj
        @expstack.push [type,
          lambda {|b, context|
            context.rc = funcobj.llvm
            context
          }
        ]
      }
    },

    :to_raw => {
      :inline_proc => lambda {|para|
        info = para[:info]
        obj = para[:receiver]

        raw = get_raw_llvm_type(obj[0].content)
        @expstack.push [RubyType.value,
          lambda {|b, context|
            context.rc = raw.llvm
            context
          }
        ]
      }
    },
  }

  InlineMethod_LLVMLIB = {
    :unsafe => {
      :inline_proc => lambda {|para|
        info = para[:info]
        ptr = para[:args][1]
        mess = "return type of LLVMLIB::unsafe"
        objtype = para[:args][0][0].content
        unsafetype = RubyType.unsafe(info[3], mess, objtype)
        @expstack.push [unsafetype,
          lambda {|b, context|
            ptrrc = ptr[1].call(b, context).rc
            ptrrc2 = ptrrc
            if ptr[0].type.is_a?(UnsafeType) then
              case ptr[0].type.type
              when LLVM_Pointer, LLVM_Struct
                ptrrc2 = b.ptr_to_int(ptrrc, VALUE)
              end
            end
            newptr = unsafetype.type.from_value(ptrrc2, b, context)
            context.rc = newptr
            context
          }
        ]
      }
    },

    :safe => {
      :inline_proc => lambda {|para|
        info = para[:info]
        ptr = para[:args][0]
        ptrllvm = ptr[0].type.type
        mess = "return type of LLVMLIB::safe"
        safetype = RubyType.new(VALUE, info[3], mess)
        @expstack.push [safetype,
          lambda {|b, context|
            ptr0 = ptr[1].call(b, context).rc
            safetype.type = PrimitiveType.new(ptr[0].type.type, nil)
            newptr = safetype.type.to_value(ptr0, b, context)
            context.rc = newptr
            context
          }
        ]
      }
    },

    :define_external_function => {
      :inline_proc => lambda {|para|
        info = para[:info]
        sigobj = para[:args][0]
        cfnobj = para[:args][1]
        rfnobj = para[:args][2]
        
        sig = sigobj[0].content
        cfuncname = cfnobj[0].content
        rfuncname = rfnobj[0].content
        mess = "External function: #{cfuncname}"
        functype = RubyType.value(info[3], mess)
        i = 0
        argtype = sig.arg_type.map do |e|
            i = i + 1
            case e
            when UnsafeType
              e
            else
              RubyType.unsafe(info[3], "Arg #{i} of #{rfuncname}", e)
            end
        end
        mess = "ret type of #{rfuncname}"
        rettype = RubyType.unsafe(info[3], mess, sig.ret_type)
        MethodDefinition::CMethod[nil][rfuncname] = {
          :cname => cfuncname,
          :argtype => argtype,
          :rettype => rettype,
          :send_self => false
        }
        @expstack.push [functype,
          lambda {|b, context|
            context.rc = 4.llvm
            context
          }
        ]
      }
    },


    :external_variable => {
      :inline_proc => lambda {|para|
        info = para[:info]
        sigobj = para[:args][0]
        cobj = para[:args][1]
        
        type = sigobj[0].content
        cvarname = cobj[0].content

        mess = "ret type of external_variable(#{cvarname})"
        vartype = RubyType.unsafe(info[3], mess, type)
        @expstack.push [vartype,
          lambda {|b, context|
            builder = context.builder
            add = builder.external_variable(cvarname, type.llvm)
            add2 = add
            case vartype.type.type
            when LLVM_Pointer, LLVM_Struct
              add2 = b.ptr_to_int(add, VALUE)
            end
            newptr = vartype.type.from_value(add2, b, context)
            context.rc = newptr
            context
          }
        ]
      }
    },

    :get_address_of_method => {
      :inline_proc => lambda {|para|
        info = para[:info]
        recobj = para[:args][1]
        mtsymobj = para[:args][0]
        
        mtsym = mtsymobj[0].content
        rec = recobj[0].content.to_sym

        mess = "Address of #{mtsym}"
        rectype = RubyType.unsafe(info[3], mess, VALUE)
        @expstack.push [rectype,
          lambda {|b, context|
            add = MethodDefinition::RubyMethod[mtsym][rec][:func]
            addval = b.ptr_to_int(add, VALUE)
            context.rc = addval
            context
          }
        ]
      }
    },

    :get_address_of_cmethod => {
      :inline_proc => lambda {|para|
        info = para[:info]
        recobj = para[:args][1]
        mtsymobj = para[:args][0]
        
        mtsym = mtsymobj[0].content
        rec = recobj[0].content
        if rec == UNDEF then
          rec = nil
        else
          rec = rec.to_sym
        end
        cname = MethodDefinition::CMethod[rec][mtsym][:cname]

        mess = "Address of #{mtsym}"
        rectype = RubyType.unsafe(info[3], mess, VALUE)
        @expstack.push [rectype,
          lambda {|b, context|
            ftype = Type.function(VALUE, [])
            builder = context.builder
            add = builder.external_function(cname, ftype)
            addval = b.ptr_to_int(add, VALUE)
            context.rc = addval
            context
          }
        ]
      }
    },

    :alloca => {
      :inline_proc => lambda {|para|
        info = para[:info]
        typeobj = para[:args][0]
        
        type = get_raw_llvm_type(typeobj[0].content)
        typtr = Type.pointer(type)
        type2 = LLVM_Pointer.new(typtr, type)

        mess = "Result of alloca"
        rectype = RubyType.unsafe(info[3], mess, type2)
        @expstack.push [rectype,
          lambda {|b, context|
            context.rc = b.alloca(type, 1)
            context
          }
        ]
      }
    },
  }

  InlineMethod_Unsafe = {
    :call => {
      :inline_proc => lambda {|para|
        info = para[:info]
        args = para[:args]
        func = para[:receiver]
        functype = func[0].type.type.member
        rettype = RubyType.unsafe(info[3], "Return type of call", functype.ret_type)
        @expstack.push [rettype,
          lambda {|b, context|
            type = functype.type
            argsv = []
            args.each do |ele|
              context = ele[1].call(b, context)
              argsv.push context.rc
            end
            context = func[1].call(b, context)
            funcptr = context.rc
            context.rc = b.call(funcptr, *argsv)
            context
          }
        ]
      }
    },

    :address_of => {
      :inline_proc => lambda {|para|
        info = para[:info]
        idx = para[:args][0]
        arr = para[:receiver]
        rettype = RubyType.unsafe(info[3], "Result of address_of", VALUE)

        rindx = idx[0].type.constant
        indx = rindx
        if rindx.is_a?(Symbol) then
          unless indx = arr[0].type.type.index_symbol[rindx]
            raise "Unkown tag #{rindx}"
          end
        end
        dstt = arr[0].type.type.member[indx]
        if dstt.is_a?(LLVM_Type) then
          dstt = dstt.type
        end
        ptr = Type.pointer(dstt)
        rettype.type.type = LLVM_Pointer.new(ptr, dstt)

        @expstack.push [rettype,
          lambda {|b, context|
            context = arr[1].call(b, context)
            arrp = context.rc
            context = idx[1].call(b, context)
            addr = b.struct_gep(arrp, indx)
            context.rc = addr
            context
          }
        ]
      }
    }
  }

  InlineMethod_Transaction = {
    :begin_transaction => {
      :inline_proc => lambda {|para|
        info = para[:info]
        if OPTION[:cache_instance_variable] == false then
          mess = "Please option \':cache_instance_variable\' to true"
          mess += "if you use Transaction mixin"
          raise mess
        end

        oldrescode = @rescode
        @rescode = lambda {|b, context|
          context = oldrescode.call(b, context)
          
          context.user_defined[:transaction] ||= {}
          trcontext = context.user_defined[:transaction]

          orgvtab = {}
          orgvtabinit = {}
          trcontext[:original_instance_vars_local] = orgvtab
          trcontext[:original_instance_vars_init] = orgvtabinit

          vtab = context.instance_vars_local_area
          vtab2 = vtab.clone
          vtab.each do |name, area|
            vtab[name] = b.alloca(VALUE, 1)
            orgvtabinit[name] = b.alloca(VALUE, 1)
          end

          lbody = context.builder.create_block
          trcontext[:body] = lbody
          b.br(lbody)
          
          fmlab = context.curln
          context.blocks_tail[fmlab] = lbody
          
          b.set_insert_point(lbody)
          
          vtab2.each do |name, area|
            orgvtab[name] = area
            oval = b.load(area)
            b.store(oval, vtab[name])
            b.store(oval, orgvtabinit[name])
          end
          trcontext[:original_instance_vars_area] = vtab
          
          context
        }
      }
    },

    :commit => {
      :inline_proc => lambda {|para|
        info = para[:info]

        oldrescode = @rescode
        @rescode = lambda {|b, context|
          context = oldrescode.call(b, context)

          trcontext = context.user_defined[:transaction]
          if trcontext == nil then
            raise "commit must use with begin_transaction"
          end

          vtab = context.instance_vars_local_area
          orgvtab = trcontext[:original_instance_vars_local]
          vtabinit = trcontext[:original_instance_vars_init]
          vtabarea = trcontext[:original_instance_vars_area]

          if vtab.size == 1 then
            # Can commit lock-free
            orgarea = orgvtab.to_a[0][1]
            orgvalue = b.load(vtabinit.to_a[0][1])
            newvalue = b.load(vtabarea.to_a[0][1])

            ftype = Type.function(VALUE, [P_VALUE, VALUE, VALUE])
            fname = "llvm.atomic.cmp.swap.i32.p0i32"
            func = context.builder.external_function(fname, ftype)
            actval = b.call(func, orgarea, orgvalue, newvalue)

            lexit = context.builder.create_block
            lretry = trcontext[:body]
            fmlab = context.curln
            context.blocks_tail[fmlab] = lexit

            cmp = b.icmp_eq(orgvalue, actval)
            b.cond_br(cmp, lexit, lretry)

            b.set_insert_point(lexit)
          else
            # Lock base commit
            raise "Not implement yet in #{info[3]}"
          end
          
          vtab.each do |name, area|
            vtab[name] = orgvtab[name]
          end

          context
        }
      }
   },

    :abort => {
      :inline_proc => lambda {|para|
        oldrescode = @rescode
        @rescode = lambda {|b, context|
          context = oldrescode.call(b, context)

          trcontext = context.user_defined[:transaction]
          if trcontext == nil then
            raise "abort must use with begin_transaction"
          end
          vtab = context.instance_vars_local_area
          orgvtab = trcontext[:original_instance_vars_local]
        
          vtab.each do |name, area|
            vtab[name] = orgvtab[name]
          end

          context
        }
      }
    },

    :do_retry => {
      :inline_proc => lambda {|para|
        oldrescode = @rescode
        @rescode = lambda {|b, context|
          context = oldrescode.call(b, context)

          trcontext = context.user_defined[:transaction]
          if trcontext == nil then
            raise "abort must use with begin_transaction"
          end

          lexit = context.builder.create_block
          lretry = trcontext[:body]
          fmlab = context.curln
          context.blocks_tail[fmlab] = lexit

          b.br(lretry)

          b.set_insert_point(lexit)
          context
        }
      }
    }
  }

  InlineMethod[:YARV2LLVM] = InlineMethod_YARV2LLVM
  InlineMethod[:"YARV2LLVM::LLVMLIB"] = InlineMethod_LLVMLIB
  InlineMethod[:LLVM] = InlineMethod_LLVM
  InlineMethod[:"YARV2LLVM::LLVMLIB::Unsafe"] = InlineMethod_Unsafe
  InlineMethod[:Transaction] = InlineMethod_Transaction
end
end
