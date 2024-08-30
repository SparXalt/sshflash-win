@echo off

rem *** sshflash-win ***
rem A fork of sshflash for Windows, by andymcca.  sshflash originally by mac2612 (https://github.com/mac2612/sshflash).
rem Version 0.3 (2023-02-01) 
rem
rem Keys Information -
rem 
rem As of version 0.3, keys are no longer used to connect via SSH.
rem This reflects the upcoming change in retroleap to remove key-based access, as the RSA standard is deprecated and this was causing issues with flashing.
SET SSH=ssh root@169.254.8.1

rem Fix the permissions on the "private key" , so ssh does not complain.
rem sshflash-win - Not required on Windows so is commented out here.
rem chmod 700 keys\id_rsa

call :show_warning
SET prefix=%~1
call :show_actionlist
echo Enter choice (1 - 3)
SET /P CHOICE=
if /I "%CHOICE%" == "1" (SET action="flash")
if /I "%CHOICE%" == "2" (SET action="dump")
if /I "%CHOICE%" == "3" (SET action="surgeon")
echo choice was %CHOICE% so action is %action%
call :show_machinelist
echo Enter choice (1 - 4)
SET /P REPLY=
if /I "%REPLY%" == "1" (SET prefix="lf1000_didj_")
if /I "%REPLY%" == "2" (SET prefix="lf1000_")
if /I "%REPLY%" == "3" (SET prefix="lf2000_")
if /I "%REPLY%" == "4" (SET prefix="lf3000_")
timeout /t 2


IF /I %action% == "flash" (
  IF /I %prefix% == "lf3000_" (call :flash_mmc "%prefix%"
) ELSE (
  call :flash_nand "%prefix%") ) ELSE ( IF /I %prefix% == "lf3000_" (call :dump_mmc "%prefix%") ELSE (call :dump_nand "%prefix%")
)
EXIT /B %ERRORLEVEL%


:show_warning
cls
echo sshflash-win ver 0.3 (forked from sshflash by mac2612 - https://github.com/mac2612/sshflash)
echo Installs a custom OS on your LeapPad/Leapster!
echo(
echo WARNING! This utility will ERASE the stock leapster OS and any other
echo data on the device. The device can be restored to stock settings using
echo the LeapFrog Connect app. Note that flashing your device will likely
echo VOID YOUR WARRANTY! Proceed at your own risk.
echo(
echo Please power off your device, and do the following -
echo(
echo Leapster Explorer - Hold the L + R shoulder buttons AND the Hint (?) button whilst powering on
echo LeapsterGS - Hold the L + R shoulder buttons whilst powering on 
echo LeapPad2 - Hold the Right arrow (portrait orientation) + Home buttons whilst powering on.
echo LeapPad3 - Hold the Down arrow (landscape orientation) + Home buttons whilst powering on.
echo(
echo You should see a screen with a green background and a picture of the device
echo connecting to a computer.
pause
EXIT /B 0

:show_machinelist
echo ----------------------------------------------------------------
echo What type of system would you like to use?
echo(
echo 1. LF1000-Didj (Didj with EmeraldBoot)
echo 2. LF1000 (Leapster Explorer)
echo 3. LF2000 (Leapster GS, LeapPad 2, LeapPad Ultra XDI)
echo 4. LF3000 (LeapPad 3, LeapPad Platinum)
EXIT /B 0

:show_actionlist
echo ----------------------------------------------------------------
echo What type of action are you performing?
echo(
echo 1. Flashing device with RetroLeap
echo 2. No flashing, dump cartridge at mtdblock3 instead
echo 3. No flashing, no dumping just boot Surgeon and connect me, please
EXIT /B 0

:boot_surgeon
SET surgeon_path=%~1
SET memloc=%~2
echo Booting the Surgeon environment...
make_cbf.exe %memloc:"=% %surgeon_path:"=% surgeon_tmp.cbf
echo Lines to write (should be a whole number) -
boot_surgeon.exe surgeon_tmp.cbf
echo Done! Waiting for Surgeon to come up...
DEL surgeon_tmp.cbf
timeout /t 15
echo Done!
EXIT /B 0

:pingtest
ping 169.254.8.1 -n 8
echo.
echo If the previous pings failed or destination host was unreachable you need to 
echo install the driver or configure the static IP of 169.254.8.10 on the ethernet gadget.
echo.
echo.
echo Would you like to test the ping again after correcting this?
CHOICE /C YN /M "Press Y for Yes, N for No."
if %ERRORLEVEL% EQU 1 call :pingtest
EXIT /B 0

:nand_part_detect
rem Probe for filesystem partition locations, they can vary based on kernel version + presence of NOR flash drivers.
rem TODO- Make the escaping less yucky...

SET SPACE=" "
SET KP=awk -e '$4 ~ \"Kernel\"  {print \"/dev/\" substr($1, 1, length($1)-1)}' /proc/mtd
rem SET "var=%SSH%%SPACE:"=%%KP%"
rem echo %SSH:"=% "%KP%"
FOR /f %%i in ('%SSH:"=% "%KP%"') do set "KERNEL_PARTITION=%%i"

SET RP=awk -e '$4 ~ \"RFS\"  {print \"/dev/\" substr($1, 1, length($1)-1)}' /proc/mtd
SET "var=%SSH%%SPACE:"=%%RP%"
FOR /f %%i in ('%SSH:"=% "%RP%"') do set "RFS_PARTITION=%%i"

echo "Detected Kernel partition=%KERNEL_PARTITION% RFS Partition=%RFS_PARTITION%"
EXIT /B 0

:nand_flash_kernel
SET kernel_path=%~1
echo(
echo "Flashing the kernel...(%kernel_path%)
%SSH% "/usr/sbin/flash_erase %KERNEL_PARTITION% 0 0"
type %kernel_path% | %SSH% "/usr/sbin/nandwrite -p" %KERNEL_PARTITION% "-"
echo Done flashing the kernel!
EXIT /B 0

:nand_flash_rfs
SET rfs_path=%~1
echo Flashing the root filesystem...
%SSH% "/usr/sbin/ubiformat -y %RFS_PARTITION%"
%SSH% "/usr/sbin/ubiattach -p %RFS_PARTITION%"
timeout /t 1
%SSH% "/usr/sbin/ubimkvol /dev/ubi0 -N RFS -m"
timeout /t 1
%SSH% "mount -t ubifs /dev/ubi0_0 /mnt/root"
echo Writing rootfs image...

rem Note: We used to use a ubifs image here, but now use a .tar.gz.
rem This removes the need to care about PEB/LEB sizes at build time,
rem which is important as some LF2000 models Ultra XDi have differing sizes.

type %rfs_path% | %SSH% "gunzip -c | tar x -f '-' -C /mnt/root"
%SSH% "umount /mnt/root"
%SSH% "/usr/sbin/ubidetach -d 0"
timeout /t 3
echo(
echo Done flashing the root filesystem!
EXIT /B 0

:nand_maybe_wipe_roms
  echo Do you want to format the roms partition? (You should do this on the first flash of retroleap) (y/n): 
  SET /P REPLY=
  if /I "%REPLY%" == "y" (
    %SSH% "/usr/sbin/ubiformat /dev/mtd3"
    %SSH% "/usr/sbin/ubiattach -p /dev/mtd3"
    %SSH% "/usr/sbin/ubimkvol /dev/ubi0 -m -N roms")
EXIT /B 0

:flash_nand
  SET prefix=%~1
  if /I %prefix:"=% == lf1000_ (set memloc="high") else (set memloc="superhigh")
  if /I %prefix:"=% == lf1000_ (set kernel="zImage_tmp.cbf") else (set kernel="%prefix:"=%uImage")
  if /I %prefix:"=% == lf1000_ (make_cbf.exe %memloc:"=% %prefix:"=%zImage %kernel:"=%)
  rem echo Debugging info - 
  rem echo(
  rem echo %memloc:"=%
  rem echo %prefix:"=%zImage
  rem echo %kernel:"=%
  rem echo(
  rem pause

  call :boot_surgeon %prefix:"=%surgeon_zImage %memloc:"=%
  call :pingtest
  rem For the first ssh command, skip hostkey checking to avoid prompting the user.
  %SSH% -o "StrictHostKeyChecking no" 'test'
  call :nand_part_detect
  call :nand_flash_kernel %kernel:"=%
  call :nand_flash_rfs %prefix:"=%rootfs.tar.gz
  call :nand_maybe_wipe_roms 
  echo Done! Rebooting the host.
  %SSH% '/sbin/reboot'
EXIT /B 0

:dump_nand
  SET prefix=%~1
IF /I %action% == "dump" (
  echo Looks like you are trying to dump a cartidge on an unsupported device
  echo You need an LF3000 device (LeapPad 3, LeapPad Platinum^) because these 
  echo present the cartridge as a block device and they have ^>128MB RAM to
  echo hold the cartridge binary while copying.
)
IF /I %action% == "surgeon" (
  if /I %prefix:"=% == lf1000_ (set memloc="high") else (set memloc="superhigh")
  if /I %prefix:"=% == lf1000_ (set kernel="zImage_tmp.cbf") else (set kernel="%prefix:"=%uImage")
  if /I %prefix:"=% == lf1000_ (make_cbf.exe %memloc:"=% %prefix:"=%zImage %kernel:"=%)
  rem echo Debugging info - 
  rem echo(
  rem echo %memloc:"=%
  rem echo %prefix:"=%zImage
  rem echo %kernel:"=%
  rem echo(
  rem pause

  call :boot_surgeon %prefix:"=%surgeon_zImage %memloc:"=%
  call :pingtest
  rem For the first ssh command, skip hostkey checking to avoid prompting the user.
  %SSH% -o "StrictHostKeyChecking no" 'test'
  echo Use the command "/sbin/poweroff" once you are done to shutdown the device.
  echo Connecting via SSH now...
  %SSH%
  )
EXIT /B 0

:mmc_flash_kernel
  SET kernel_path=%~1
  echo Flashing the kernel...
  rem TODO: This directory structure should be included in surgeon images.
  %SSH% "mkdir /mnt/boot"
  rem TODO: This assumes a specific partition layout - not sure if this is the case for all devices?
  %SSH% "mount /dev/mmcblk0p2 /mnt/boot"
  type %kernel_path% | %SSH% "cat - > /mnt/boot/uImage"
  %SSH% "umount /dev/mmcblk0p2"
  echo Done flashing the kernel!
EXIT /B 0

:mmc_flash_rfs
  SET rfs_path=%~1
  rem Size of the rootfs to be flashed, in bytes.
  echo Flashing the root filesystem...
  %SSH% "/sbin/mkfs.ext4 -F -L RFS -O ^metadata_csum /dev/mmcblk0p3"
  rem TODO: This directory structure should be included in surgeon images.
  %SSH% "mkdir /mnt/root"
  %SSH% "mount -t ext4 /dev/mmcblk0p3 /mnt/root"
  echo Writing rootfs image... 
  type %rfs_path% | %SSH% "gunzip -c | tar x -f '-' -C /mnt/root"
  %SSH% "umount /mnt/root"
  echo Done flashing the root filesystem!
EXIT /B 0

:flash_mmc
  SET prefix=%~1
  call :boot_surgeon %prefix%surgeon_zImage superhigh
  call :pingtest
  rem For the first ssh command, skip hostkey checking to avoid prompting the user.
  %SSH% -o "StrictHostKeyChecking no" 'test'
  call :mmc_flash_kernel %prefix%uImage
  call :mmc_flash_rfs %prefix%rootfs.tar.gz
  echo(
  echo Done! Rebooting the host.
  timeout /t 3
  %SSH% '/sbin/reboot'
EXIT /B 0

:dump_mmc
  SET prefix=%~1
  call :boot_surgeon %prefix%surgeon_zImage superhigh
  call :pingtest
  for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
  set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%" & set "Min=%dt:~10,2%" & set "Sec=%dt:~12,2%"
  set "timestamp=%YYYY%%MM%%DD%_%HH%%Min%%Sec%"
  rem For the first ssh command, skip hostkey checking to avoid prompting the user.
  %SSH% -o "StrictHostKeyChecking no" 'test'
IF /I %action% == "dump" (
  echo .
  echo Dumping ROM to device RAM
  %SSH% "dd if=/dev/mtdblock3 of=/tmp/dump.bin"
  echo .
  echo Copying ROM to Windows PC
  scp root@169.254.8.1:/tmp/dump.bin .\dump%timestamp%.bin
  echo .
  echo File created: 
  echo dump%timestamp%.bin
  echo MD5 Hash
  certutil -hashfile .\dump%timestamp%.bin MD5 | find /i /v "md5" | find /i /v "certutil"
  echo .
  echo .
  echo Done! You can now powerdown the device, reinsert the cartridge
  echo and repeat the dump again to verify that the MD5 hashes match.
  )
IF /I %action% == "surgeon" (
  echo Use the command "/sbin/poweroff" once you are done to shutdown the device.
  echo Connecting via SSH now...
  %SSH%
  )
EXIT /B 0

