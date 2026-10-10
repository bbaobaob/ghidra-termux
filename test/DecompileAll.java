// DecompileAll.java -- Ghidra headless postScript: decompile every function
// in the current program to C and write the result to a single file.
//
// This exercises the native `decompile` binary (linux_arm_64 build) and is the
// end-to-end proof that the ARM64 port works.
//
// Usage (headless):
//   ghidra-termux <projdir> <proj> -import ./target \
//     -scriptPath <this-dir> -postScript DecompileAll.java out.c

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.decompiler.DecompInterface;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

import java.io.FileWriter;
import java.io.PrintWriter;

public class DecompileAll extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outPath = (args.length > 0) ? args[0] : "decompiled.c";

        DecompInterface di = new DecompInterface();
        DecompileOptions options = new DecompileOptions();
        di.setOptions(options);
        di.openProgram(currentProgram);

        PrintWriter out = new PrintWriter(new FileWriter(outPath));
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        int total = 0, ok = 0;
        while (it.hasNext() && !monitor.isCancelled()) {
            Function f = it.next();
            total++;
            DecompileResults res = di.decompileFunction(f, 120, monitor);
            if (res != null && res.decompileCompleted() && res.getDecompiledFunction() != null) {
                out.println("// ==== " + f.getName() + " @ " + f.getEntryPoint() + " ====");
                out.println(res.getDecompiledFunction().getC());
                ok++;
            } else {
                out.println("// ==== " + f.getName() + " : DECOMPILE FAILED ====");
            }
        }
        out.close();
        di.dispose();
        println("DecompileAll: " + ok + "/" + total + " functions -> " + outPath);
    }
}
