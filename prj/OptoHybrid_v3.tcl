# 
# Project automation script for OptoHybrid_v3 
# 
# Created for ISE version 14.7
# 
# This file contains several Tcl procedures (procs) that you can use to automate
# your project by running from xtclsh or the Project Navigator Tcl console.
# If you load this file (using the Tcl command: source OptoHybrid_v3.tcl), then you can
# run any of the procs included here.
# 
# This script is generated assuming your project has HDL sources.
# Several of the defined procs won't apply to an EDIF or NGC based project.
# If that is the case, simply remove them from this script.
# 
# You may also edit any of these procs to customize them. See comments in each
# proc for more instructions.
# 
# This file contains the following procedures:
# 
# Top Level procs (meant to be called directly by the user):
#    run_process: you can use this top-level procedure to run any processes
#        that you choose to by adding and removing comments, or by
#        adding new entries.
#    rebuild_project: you can alternatively use this top-level procedure
#        to recreate your entire project, and the run selected processes.
# 
# Lower Level (helper) procs (called under in various cases by the top level procs):
#    show_help: print some basic information describing how this script works
#    add_source_files: adds the listed source files to your project.
#    set_project_props: sets the project properties that were in effect when this
#        script was generated.
#    create_libraries: creates and adds file to VHDL libraries that were defined when
#        this script was generated.
#    set_process_props: set the process properties as they were set for your project
#        when this script was generated.
# 

set myProject "OptoHybrid_v3"
set myScript "OptoHybrid_v3.tcl"

# 
# Main (top-level) routines
# 
# run_process
# This procedure is used to run processes on an existing project. You may comment or
# uncomment lines to control which processes are run. This routine is set up to run
# the Implement Design and Generate Programming File processes by default. This proc
# also sets process properties as specified in the "set_process_props" proc. Only
# those properties which have values different from their current settings in the project
# file will be modified in the project.
# 
proc run_process {} {

   global myScript
   global myProject

   ## put out a 'heartbeat' - so we know something's happening.
   puts "\n$myScript: running ($myProject)...\n"

   if { ! [ open_project ] } {
      return false
   }

   set_process_props
   #
   # Remove the comment characters (#'s) to enable the following commands 
   process run "Synthesize"
   process run "Translate"
   process run "Map"
   process run "Place & Route"
   #
   set task "Implement Design"
   if { ! [run_task $task] } {
      puts "$myScript: $task run failed, check run output for details."
      project close
      return
   }

   set task "Generate Programming File"
   if { ! [run_task $task] } {
      puts "$myScript: $task run failed, check run output for details."
      project close
      return
   }

   puts "Run completed (successfully)."
   project close

}

# 
# rebuild_project
# 
# This procedure renames the project file (if it exists) and recreates the project.
# It then sets project properties and adds project sources as specified by the
# set_project_props and add_source_files support procs. It recreates VHDL Libraries
# as they existed at the time this script was generated.
# 
# It then calls run_process to set process properties and run selected processes.
# 
proc rebuild_project {} {

   global myScript
   global myProject

   project close
   ## put out a 'heartbeat' - so we know something's happening.
   puts "\n$myScript: Rebuilding ($myProject)...\n"

   set proj_exts [ list ise xise gise ]
   foreach ext $proj_exts {
      set proj_name "${myProject}.$ext"
      if { [ file exists $proj_name ] } { 
         file delete $proj_name
      }
   }

   project new $myProject
   set_project_props
   add_source_files
   create_libraries
   puts "$myScript: project rebuild completed."

   run_process

}

# 
# Support Routines
# 

# 
proc run_task { task } {

   # helper proc for run_process

   puts "Running '$task'"
   set result [ process run "$task" ]
   #
   # check process status (and result)
   set status [ process get $task status ]
   if { ( ( $status != "up_to_date" ) && \
            ( $status != "warnings" ) ) || \
         ! $result } {
      return false
   }
   return true
}

# 
# show_help: print information to help users understand the options available when
#            running this script.
# 
proc show_help {} {

   global myScript

   puts ""
   puts "usage: xtclsh $myScript <options>"
   puts "       or you can run xtclsh and then enter 'source $myScript'."
   puts ""
   puts "options:"
   puts "   run_process       - set properties and run processes."
   puts "   rebuild_project   - rebuild the project from scratch and run processes."
   puts "   set_project_props - set project properties (device, speed, etc.)"
   puts "   add_source_files  - add source files"
   puts "   create_libraries  - create vhdl libraries"
   puts "   set_process_props - set process property values"
   puts "   show_help         - print this message"
   puts ""
}

proc open_project {} {

   global myScript
   global myProject

   if { ! [ file exists ${myProject}.xise ] } { 
      ## project file isn't there, rebuild it.
      puts "Project $myProject not found. Use project_rebuild to recreate it."
      return false
   }

   project open $myProject

   return true

}
# 
# set_project_props
# 
# This procedure sets the project properties as they were set in the project
# at the time this script was generated.
# 
proc set_project_props {} {

   global myScript

   if { ! [ open_project ] } {
      return false
   }

   puts "$myScript: Setting project properties..."

   project set family "Virtex6"
   project set device "xc6vlx130t"
   project set package "ff1156"
   project set speed "-1"
   project set top_level_module_type "HDL"
   project set synthesis_tool "XST (VHDL/Verilog)"
   project set simulator "ISim (VHDL/Verilog)"
   project set "Preferred Language" "VHDL"
   project set "Enable Message Filtering" "true"

}


# 
# add_source_files
# 
# This procedure add the source files that were known to the project at the
# time this script was generated.
# 
proc add_source_files {} {

   global myScript

   if { ! [ open_project ] } {
      return false
   }

   puts "$myScript: Adding sources to project..."

   xfile add "../src/chipscope_ila.cdc"
   xfile add "../src/control/adc.vhd"
   xfile add "../src/control/control.vhd"
   xfile add "../src/control/device_dna.v"
   xfile add "../src/control/external.v"
   xfile add "../src/control/fmm.v"
   xfile add "../src/control/led_control.v"
   xfile add "../src/control/reset.v"
   xfile add "../src/control/ttc.v"
   xfile add "../src/gbt/gbt.vhd"
   xfile add "../src/gbt/gbt_link.vhd"
   xfile add "../src/gbt/gbt_rx.vhd"
   xfile add "../src/gbt/gbt_serdes.vhd"
   xfile add "../src/gbt/gbt_tx.vhd"
   xfile add "../src/gbt/link_request.vhd"
   xfile add "../src/gbt/test/link_oh_fpga_rx.vhd"
   xfile add "../src/gbt/test/link_oh_fpga_tx.vhd"
   xfile add "../src/gbt/to_gbt_ser.vhd"
   xfile add "../src/ip_cores/clk_gen.xco"
   xfile add "../src/ip_cores/fifo_request_rx.xco"
   xfile add "../src/ip_cores/fifo_request_tx.xco"
   xfile add "../src/ip_cores/gbt_clocking.xco"
   xfile add "../src/ip_cores/sem.xco"
   xfile add "../src/ip_cores/xadc.xco"
   xfile add "../src/optohybrid_tb.v"
   xfile add "../src/optohybrid_top.vhd"
   xfile add "../src/pkg/ipbus_pkg.vhd"
   xfile add "../src/pkg/param_pkg.vhd"
   xfile add "../src/pkg/registers.vhd"
   xfile add "../src/pkg/types_pkg.vhd"
   xfile add "../src/sbit_cluster_packer/source/cluster_packer.v"
   xfile add "../src/sbit_cluster_packer/source/consecutive_count.v"
   xfile add "../src/sbit_cluster_packer/source/count_clusters.v"
   xfile add "../src/sbit_cluster_packer/source/encoder_mux.v"
   xfile add "../src/sbit_cluster_packer/source/first8of1536.v"
   xfile add "../src/sbit_cluster_packer/source/lac.v"
   xfile add "../src/sbit_cluster_packer/source/merge16.v"
   xfile add "../src/sbit_cluster_packer/source/merge16_light.v"
   xfile add "../src/sbit_cluster_packer/source/priority768.v"
   xfile add "../src/sbit_cluster_packer/source/truncate_clusters.v"
   xfile add "../src/sbit_cluster_packer/source/x_oneshot.v"
   xfile add "../src/trigger/channel_to_strip.vhd"
   xfile add "../src/trigger/link/gem_fiber_out.v"
   xfile add "../src/trigger/link/trg_tx_buf_bypass.v"
   xfile add "../src/trigger/link/trg_tx_buf_bypass_gtx.v"
   xfile add "../src/trigger/link/trigger_links.v"
   xfile add "../src/trigger/link/tx_sync.v"
   xfile add "../src/trigger/sbits.vhd"
   xfile add "../src/trigger/trig_alignment/frame_aligner.v"
   xfile add "../src/trigger/trig_alignment/test/frame_aligner_tb.v"
   xfile add "../src/trigger/trig_alignment/test/oversampler_tb.v"
   xfile add "../src/trigger/trig_alignment/test/trig_alignment_tb.v"
   xfile add "../src/trigger/trig_alignment/trig_alignment.vhd"
   xfile add "../src/trigger/trig_alignment/trig_pkg.vhd"
   xfile add "../src/trigger/trigger.vhd"
   xfile add "../src/ucf/clocking.ucf"
   xfile add "../src/ucf/gbt.ucf"
   xfile add "../src/ucf/misc.ucf"
   xfile add "../src/utils/6b8b.vhd"
   xfile add "../src/utils/6b8b_pkg.vhd"
   xfile add "../src/utils/8b6b.vhd"
   xfile add "../src/utils/DRU.vhd"
   xfile add "../src/utils/OVERSAMPLE.vhd"
   xfile add "../src/utils/bitslip.vhd"
   xfile add "../src/utils/clocking.vhd"
   xfile add "../src/utils/counter_snap.vhd"
   xfile add "../src/utils/cylon.v"
   xfile add "../src/utils/err_indicator.v"
   xfile add "../src/utils/iodelay.vhd"
   xfile add "../src/utils/iserdes.vhd"
   xfile add "../src/utils/progress_bar.vhd"
   xfile add "../src/utils/sem_mon.vhd"
   xfile add "../src/utils/synchronizer.vhd"
   xfile add "../src/utils/x_flashsm.v"
   xfile add "../src/wb/ipb_switch.vhd"
   xfile add "../src/wb/ipbus_slave.vhd"
   xfile add "../src/wb/wb_switch.vhd"
   puts ""
   puts "WARNING: project contains IP cores, synthesis will fail if any of the cores require regenerating."
   puts ""

   # Set the Top Module as well...
   project set top "Behavioral" "optohybrid_top"

   puts "$myScript: project sources reloaded."

} ; # end add_source_files

# 
# create_libraries
# 
# This procedure defines VHDL libraries and associates files with those libraries.
# It is expected to be used when recreating the project. Any libraries defined
# when this script was generated are recreated by this procedure.
# 
proc create_libraries {} {

   global myScript

   if { ! [ open_project ] } {
      return false
   }

   puts "$myScript: Creating libraries..."


   # must close the project or library definitions aren't saved.
   project save

} ; # end create_libraries

# 
# set_process_props
# 
# This procedure sets properties as requested during script generation (either
# all of the properties, or only those modified from their defaults).
# 
proc set_process_props {} {

   global myScript

   if { ! [ open_project ] } {
      return false
   }

   puts "$myScript: setting process properties..."

   project set "Compiled Library Directory" "\$XILINX/<language>/<simulator>"
   project set "Global Optimization" "Speed" -process "Map"
   project set "Use DSP Block" "Auto" -process "Synthesize - XST"
   project set "DCI Update Mode" "As Required" -process "Generate Programming File"
   project set "Enable Cyclic Redundancy Checking (CRC)" "true" -process "Generate Programming File"
   project set "Configuration Rate" "33" -process "Generate Programming File"
   project set "Pack I/O Registers/Latches into IOBs" "For Inputs and Outputs" -process "Map"
   project set "Place And Route Mode" "Route Only" -process "Place & Route"
   project set "Number of Clock Buffers" "32" -process "Synthesize - XST"
   project set "Max Fanout" "10000" -process "Synthesize - XST"
   project set "Use Clock Enable" "Auto" -process "Synthesize - XST"
   project set "Use Synchronous Reset" "Auto" -process "Synthesize - XST"
   project set "Use Synchronous Set" "Auto" -process "Synthesize - XST"
   project set "Regenerate Core" "Under Current Project Setting" -process "Regenerate Core"
   project set "Filter Files From Compile Order" "true"
   project set "Last Applied Goal" "Optohybrid"
   project set "Last Applied Strategy" "Performance with IOB Packing;/media/psf/Dropbox/CMS/Firmware/OptoHybridv3/prj/Optohybrid strategy.xds"
   project set "Last Unlock Status" "true"
   project set "Manual Compile Order" "false"
   project set "Placer Effort Level" "High" -process "Map"
   project set "Extra Cost Tables" "0" -process "Map"
   project set "LUT Combining" "Auto" -process "Map"
   project set "Combinatorial Logic Optimization" "true" -process "Map"
   project set "Starting Placer Cost Table (1-100)" "28" -process "Map"
   project set "Power Reduction" "Off" -process "Map"
   project set "Report Fastest Path(s) in Each Constraint" "true" -process "Generate Post-Place & Route Static Timing"
   project set "Generate Datasheet Section" "false" -process "Generate Post-Place & Route Static Timing"
   project set "Generate Timegroups Section" "false" -process "Generate Post-Place & Route Static Timing"
   project set "Report Fastest Path(s) in Each Constraint" "true" -process "Generate Post-Map Static Timing"
   project set "Generate Datasheet Section" "true" -process "Generate Post-Map Static Timing"
   project set "Generate Timegroups Section" "false" -process "Generate Post-Map Static Timing"
   project set "Project Description" ""
   project set "Property Specification in Project File" "Store all values"
   project set "Reduce Control Sets" "Auto" -process "Synthesize - XST"
   project set "Shift Register Minimum Size" "2" -process "Synthesize - XST"
   project set "Case Implementation Style" "None" -process "Synthesize - XST"
   project set "RAM Extraction" "true" -process "Synthesize - XST"
   project set "ROM Extraction" "true" -process "Synthesize - XST"
   project set "FSM Encoding Algorithm" "Auto" -process "Synthesize - XST"
   project set "Optimization Goal" "Speed" -process "Synthesize - XST"
   project set "Optimization Effort" "High" -process "Synthesize - XST"
   project set "Resource Sharing" "false" -process "Synthesize - XST"
   project set "Shift Register Extraction" "true" -process "Synthesize - XST"
   project set "User Browsed Strategy Files" "/media/psf/Dropbox/CMS/Firmware/OptoHybridv3/prj/Optohybrid strategy.xds"
   project set "VHDL Source Analysis Standard" "VHDL-200X"
   project set "Analysis Effort Level" "Standard" -process "Analyze Power Distribution (XPower Analyzer)"
   project set "Analysis Effort Level" "Standard" -process "Generate Text Power Report"
   project set "Input TCL Command Script" "" -process "Generate Text Power Report"
   project set "Load Physical Constraints File" "Default" -process "Analyze Power Distribution (XPower Analyzer)"
   project set "Load Physical Constraints File" "Default" -process "Generate Text Power Report"
   project set "Load Simulation File" "Default" -process "Analyze Power Distribution (XPower Analyzer)"
   project set "Load Simulation File" "Default" -process "Generate Text Power Report"
   project set "Load Setting File" "" -process "Analyze Power Distribution (XPower Analyzer)"
   project set "Load Setting File" "" -process "Generate Text Power Report"
   project set "Setting Output File" "" -process "Generate Text Power Report"
   project set "Produce Verbose Report" "false" -process "Generate Text Power Report"
   project set "Other XPWR Command Line Options" "" -process "Generate Text Power Report"
   project set "Essential Bits" "false" -process "Generate Programming File"
   project set "Encrypt Bitstream" "false" -process "Generate Programming File"
   project set "JTAG to System Monitor Connection" "Enable" -process "Generate Programming File"
   project set "User Access Register Value" "None" -process "Generate Programming File"
   project set "Other Bitgen Command Line Options" "" -process "Generate Programming File"
   project set "Maximum Signal Name Length" "20" -process "Generate IBIS Model"
   project set "Show All Models" "false" -process "Generate IBIS Model"
   project set "Disable Detailed Package Model Insertion" "false" -process "Generate IBIS Model"
   project set "Launch SDK after Export" "true" -process "Export Hardware Design To SDK with Bitstream"
   project set "Launch SDK after Export" "true" -process "Export Hardware Design To SDK without Bitstream"
   project set "Target UCF File Name" "" -process "Back-annotate Pin Locations"
   project set "Ignore User Timing Constraints" "false" -process "Map"
   project set "Register Ordering" "4" -process "Map"
   project set "Use RLOC Constraints" "Yes" -process "Map"
   project set "Other Map Command Line Options" "" -process "Map"
   project set "Use LOC Constraints" "true" -process "Translate"
   project set "Other Ngdbuild Command Line Options" "" -process "Translate"
   project set "Use 64-bit PlanAhead on 64-bit Systems" "true" -process "Floorplan Area/IO/Logic (PlanAhead)"
   project set "Use 64-bit PlanAhead on 64-bit Systems" "true" -process "I/O Pin Planning (PlanAhead) - Pre-Synthesis"
   project set "Use 64-bit PlanAhead on 64-bit Systems" "true" -process "I/O Pin Planning (PlanAhead) - Post-Synthesis"
   project set "Ignore User Timing Constraints" "false" -process "Place & Route"
   project set "Other Place & Route Command Line Options" "" -process "Place & Route"
   project set "BPI Reads Per Page" "1" -process "Generate Programming File"
   project set "Configuration Pin Busy" "Pull Up" -process "Generate Programming File"
   project set "Configuration Clk (Configuration Pins)" "Pull Up" -process "Generate Programming File"
   project set "UserID Code (8 Digit Hexadecimal)" "0xFFFFFFFF" -process "Generate Programming File"
   project set "Configuration Pin CS" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin DIn" "Pull Up" -process "Generate Programming File"
   project set "Disable JTAG Connection" "false" -process "Generate Programming File"
   project set "Configuration Pin Done" "Pull Up" -process "Generate Programming File"
   project set "Create ASCII Configuration File" "false" -process "Generate Programming File"
   project set "Create Binary Configuration File" "false" -process "Generate Programming File"
   project set "Create Bit File" "true" -process "Generate Programming File"
   project set "Enable BitStream Compression" "false" -process "Generate Programming File"
   project set "Run Design Rules Checker (DRC)" "true" -process "Generate Programming File"
   project set "Create IEEE 1532 Configuration File" "false" -process "Generate Programming File"
   project set "Create ReadBack Data Files" "false" -process "Generate Programming File"
   project set "Configuration Pin HSWAPEN" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin Init" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin M0" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin M1" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin M2" "Pull Up" -process "Generate Programming File"
   project set "Configuration Pin Program" "Pull Up" -process "Generate Programming File"
   project set "Power Down Device if Over Safe Temperature" "true" -process "Generate Programming File"
   project set "Configuration Pin RdWr" "Pull Up" -process "Generate Programming File"
   project set "Starting Address for Fallback Configuration" "None" -process "Generate Programming File"
   project set "JTAG Pin TCK" "Pull Up" -process "Generate Programming File"
   project set "JTAG Pin TDI" "Pull Up" -process "Generate Programming File"
   project set "JTAG Pin TDO" "Pull Up" -process "Generate Programming File"
   project set "JTAG Pin TMS" "Pull Up" -process "Generate Programming File"
   project set "Unused IOB Pins" "Pull Down" -process "Generate Programming File"
   project set "Watchdog Timer Mode" "Off" -process "Generate Programming File"
   project set "Security" "Enable Readback and Reconfiguration" -process "Generate Programming File"
   project set "Done (Output Events)" "Default (4)" -process "Generate Programming File"
   project set "Drive Done Pin High" "false" -process "Generate Programming File"
   project set "Enable Outputs (Output Events)" "Default (5)" -process "Generate Programming File"
   project set "Wait for DCI Match (Output Events)" "Auto" -process "Generate Programming File"
   project set "Wait for PLL Lock (Output Events)" "No Wait" -process "Generate Programming File"
   project set "Release Write Enable (Output Events)" "Default (6)" -process "Generate Programming File"
   project set "FPGA Start-Up Clock" "CCLK" -process "Generate Programming File"
   project set "Enable Internal Done Pipe" "true" -process "Generate Programming File"
   project set "Allow Logic Optimization Across Hierarchy" "true" -process "Map"
   project set "Maximum Compression" "false" -process "Map"
   project set "Generate Detailed MAP Report" "true" -process "Map"
   project set "Map Slice Logic into Unused Block RAMs" "true" -process "Map"
   project set "Perform Timing-Driven Packing and Placement" "false"
   project set "Trim Unconnected Signals" "true" -process "Map"
   project set "Create I/O Pads from Ports" "false" -process "Translate"
   project set "Macro Search Path" "" -process "Translate"
   project set "Netlist Translation Type" "Timestamp" -process "Translate"
   project set "User Rules File for Netlister Launcher" "" -process "Translate"
   project set "Allow Unexpanded Blocks" "false" -process "Translate"
   project set "Allow Unmatched LOC Constraints" "false" -process "Translate"
   project set "Allow Unmatched Timing Group Constraints" "false" -process "Translate"
   project set "Perform Advanced Analysis" "true" -process "Generate Post-Place & Route Static Timing"
   project set "Report Paths by Endpoint" "3" -process "Generate Post-Place & Route Static Timing"
   project set "Report Type" "Verbose Report" -process "Generate Post-Place & Route Static Timing"
   project set "Number of Paths in Error/Verbose Report" "3" -process "Generate Post-Place & Route Static Timing"
   project set "Stamp Timing Model Filename" "" -process "Generate Post-Place & Route Static Timing"
   project set "Report Unconstrained Paths" "400" -process "Generate Post-Place & Route Static Timing"
   project set "Perform Advanced Analysis" "false" -process "Generate Post-Map Static Timing"
   project set "Report Paths by Endpoint" "3" -process "Generate Post-Map Static Timing"
   project set "Report Type" "Verbose Report" -process "Generate Post-Map Static Timing"
   project set "Number of Paths in Error/Verbose Report" "3" -process "Generate Post-Map Static Timing"
   project set "Report Unconstrained Paths" "100" -process "Generate Post-Map Static Timing"
   project set "Add I/O Buffers" "true" -process "Synthesize - XST"
   project set "Global Optimization Goal" "AllClockNets" -process "Synthesize - XST"
   project set "Keep Hierarchy" "No" -process "Synthesize - XST"
   project set "Register Balancing" "Yes" -process "Synthesize - XST"
   project set "Register Duplication" "true" -process "Synthesize - XST"
   project set "Library for Verilog Sources" "" -process "Synthesize - XST"
   project set "Export Results to XPower Estimator" "" -process "Generate Text Power Report"
   project set "Asynchronous To Synchronous" "false" -process "Synthesize - XST"
   project set "Automatic BRAM Packing" "false" -process "Synthesize - XST"
   project set "BRAM Utilization Ratio" "100" -process "Synthesize - XST"
   project set "Bus Delimiter" "<>" -process "Synthesize - XST"
   project set "Case" "Maintain" -process "Synthesize - XST"
   project set "Cores Search Directories" "" -process "Synthesize - XST"
   project set "Cross Clock Analysis" "false" -process "Synthesize - XST"
   project set "DSP Utilization Ratio" "100" -process "Synthesize - XST"
   project set "Equivalent Register Removal" "true" -process "Synthesize - XST"
   project set "FSM Style" "LUT" -process "Synthesize - XST"
   project set "Generate RTL Schematic" "Yes" -process "Synthesize - XST"
   project set "Generics, Parameters" "" -process "Synthesize - XST"
   project set "Hierarchy Separator" "/" -process "Synthesize - XST"
   project set "HDL INI File" "" -process "Synthesize - XST"
   project set "LUT Combining" "No" -process "Synthesize - XST"
   project set "Library Search Order" "" -process "Synthesize - XST"
   project set "Netlist Hierarchy" "As Optimized" -process "Synthesize - XST"
   project set "Optimize Instantiated Primitives" "false" -process "Synthesize - XST"
   project set "Pack I/O Registers into IOBs" "Yes" -process "Synthesize - XST"
   project set "Power Reduction" "false" -process "Synthesize - XST"
   project set "Read Cores" "true" -process "Synthesize - XST"
   project set "LUT-FF Pairs Utilization Ratio" "100" -process "Synthesize - XST"
   project set "Use Synthesis Constraints File" "true" -process "Synthesize - XST"
   project set "Verilog Include Directories" "" -process "Synthesize - XST"
   project set "Verilog Macros" "" -process "Synthesize - XST"
   project set "Work Directory" "" -process "Synthesize - XST"
   project set "Write Timing Constraints" "false" -process "Synthesize - XST"
   project set "Other XST Command Line Options" "" -process "Synthesize - XST"
   project set "Timing Mode" "Performance Evaluation" -process "Map"
   project set "Generate Asynchronous Delay Report" "false" -process "Place & Route"
   project set "Generate Clock Region Report" "true" -process "Place & Route"
   project set "Generate Post-Place & Route Power Report" "true" -process "Place & Route"
   project set "Generate Post-Place & Route Simulation Model" "false" -process "Place & Route"
   project set "Power Reduction" "false" -process "Place & Route"
   project set "Place & Route Effort Level (Overall)" "High" -process "Place & Route"
   project set "Auto Implementation Compile Order" "true"
   project set "Equivalent Register Removal" "false" -process "Map"
   project set "Placer Extra Effort" "Normal" -process "Map"
   project set "Power Activity File" "" -process "Map"
   project set "Register Duplication" "On" -process "Map"
   project set "Generate Constraints Interaction Report" "true" -process "Generate Post-Map Static Timing"
   project set "Synthesis Constraints File" "" -process "Synthesize - XST"
   project set "RAM Style" "Auto" -process "Synthesize - XST"
   project set "Maximum Number of Lines in Report" "1000" -process "Generate Text Power Report"
   project set "AES Initial Vector" "" -process "Generate Programming File"
   project set "HMAC Key (Hex String)" "" -process "Generate Programming File"
   project set "Encrypt Key Select" "BBRAM" -process "Generate Programming File"
   project set "AES Key (Hex String)" "" -process "Generate Programming File"
   project set "Input Encryption Key File" "" -process "Generate Programming File"
   project set "Output File Name" "optohybrid_top" -process "Generate IBIS Model"
   project set "Timing Mode" "Performance Evaluation" -process "Place & Route"
   project set "Cycles for First BPI Page Read" "1" -process "Generate Programming File"
   project set "Enable Debugging of Serial Mode BitStream" "false" -process "Generate Programming File"
   project set "Create Logic Allocation File" "false" -process "Generate Programming File"
   project set "Create Mask File" "false" -process "Generate Programming File"
   project set "Watchdog Timer Value" "0x000000" -process "Generate Programming File"
   project set "Allow SelectMAP Pins to Persist" "false" -process "Generate Programming File"
   project set "Enable Multi-Threading" "2" -process "Map"
   project set "Generate Constraints Interaction Report" "false" -process "Generate Post-Place & Route Static Timing"
   project set "Move First Flip-Flop Stage" "false" -process "Synthesize - XST"
   project set "Move Last Flip-Flop Stage" "false" -process "Synthesize - XST"
   project set "ROM Style" "Auto" -process "Synthesize - XST"
   project set "Safe Implementation" "No" -process "Synthesize - XST"
   project set "Power Activity File" "" -process "Place & Route"
   project set "Extra Effort (Highest PAR level only)" "Normal" -process "Place & Route"
   project set "Fallback Reconfiguration" "Enable" -process "Generate Programming File"
   project set "Enable Multi-Threading" "4" -process "Place & Route"
   project set "Functional Model Target Language" "VHDL" -process "View HDL Source"
   project set "Change Device Speed To" "-1" -process "Generate Post-Place & Route Static Timing"
   project set "Change Device Speed To" "-1" -process "Generate Post-Map Static Timing"

   puts "$myScript: project property values set."

} ; # end set_process_props

proc main {} {

   if { [llength $::argv] == 0 } {
      show_help
      return true
   }

   foreach option $::argv {
      switch $option {
         "show_help"           { show_help }
         "run_process"         { run_process }
         "rebuild_project"     { rebuild_project }
         "set_project_props"   { set_project_props }
         "add_source_files"    { add_source_files }
         "create_libraries"    { create_libraries }
         "set_process_props"   { set_process_props }
         default               { puts "unrecognized option: $option"; show_help }
      }
   }
}

if { $tcl_interactive } {
   show_help
} else {
   if {[catch {main} result]} {
      puts "$myScript failed: $result."
   }
}

