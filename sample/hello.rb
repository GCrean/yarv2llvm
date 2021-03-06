m = LLVM::Module.new('hello') 
LLVM::ExecutionEngine.get(m)
p_char = Type.pointer(Type::Int8Ty)
#ftype = LLVM::function(Type::Int32Ty, [p_char]) 
ftype = Type.function(Type::Int32Ty, [p_char]) 
ftype = ftype.to_raw
printf = m.external_function('printf', ftype) 
#ftype = LLVM::function(Type::Int32Ty, []) 
ftype = Type.function(Type::Int32Ty, []) 
ftype = ftype.to_raw
main = m.get_or_insert_function('main', ftype) 
b = main.create_block.builder
strptr = b.create_global_string_ptr("Hello World! \n")
b.call(printf, strptr)
b.return(strptr)
#b.return(LLVM::Value.get_constant(Type::Int32Ty, 0))
LLVM::ExecutionEngine.run_function(main) 
