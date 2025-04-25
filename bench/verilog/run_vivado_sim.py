import os
import subprocess

rtl_dir = "../../rtl"
tb_dir = "./"
wb2axip_dir = "./wb2axip"
top_tb = "sata_dev"
sim_output_log = "sim_output.txt"
tcl_output_log = "tcl_output.txt"

# vivado path
vivado_bin = "/tools/Xilinx/Vivado/2024.1/bin/vivado"

project_dir = "prj"
if not os.path.exists(project_dir):
    os.makedirs(project_dir)

# add rtl files
rtl_files = [os.path.join(rtl_dir, f) for f in os.listdir(rtl_dir) if f.endswith(".v")]
rtl_files_tcl = " ".join([f'"{file}"' for file in rtl_files])

# add sim files
tb_files = [os.path.join(tb_dir, f) for f in os.listdir(tb_dir) if f.endswith(".v")]
tb_files_tcl = " ".join([f'"{file}"' for file in tb_files])

wb2axip_files = [os.path.join(wb2axip_dir, f) for f in os.listdir(wb2axip_dir) if f.endswith(".v")]
wb2axip_tcl = " ".join([f'"{file}"' for file in wb2axip_files])

# create vivado command file
tcl_script = f"""
create_project -force sata {project_dir} -part xc7a200tfbg676-2
set_property target_language Verilog [current_project]
add_files -fileset sources_1 {rtl_files_tcl}
add_files -fileset sim_1 {tb_files_tcl}
add_files -fileset sim_1 {wb2axip_tcl}
set_property top {top_tb} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
puts "Simulation Completed"
close_project
exit
"""

# save tcl script
tcl_filename = "run_vivado_sim.tcl"
with open(tcl_filename, "w") as f:
    f.write(tcl_script)

# run vivado
cmd = [vivado_bin, "-mode", "batch", "-source", tcl_filename]

# save output file
#with open(output_log, "w") as log_file:
#    subprocess.run(cmd, stdout=log_file, stderr=log_file)

with open(tcl_output_log, "w") as tcl_log, open(sim_output_log, "w") as sim_log:
    # save sim outputs to 'sim_log', save .tcl outputs to 'tcl_log'
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    
    for line in process.stdout:
        decoded_line = line.decode("utf-8")
        if "Vivado Simulator" in decoded_line:
            sim_log.write(decoded_line)
        else:
            tcl_log.write(decoded_line)

# clean up
os.remove(tcl_filename)
os.system("rm -rf *.jou *.log .Xil/")
