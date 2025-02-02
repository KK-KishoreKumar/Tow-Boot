{ amlogicFirmware, amlogicGXL, rockchipRK399 }:

let
  # Re-used for two boards.
  rocRk3399Pc = { defconfig }: rockchipRK399 {
    # Switching between board with and without mezzanine is permitted.
    # It is the same board, with a different accessory.
    boardIdentifier = "libreComputer-rocRk3399Pc";
    inherit defconfig;
    patches = [
      ./0001-rk3399-roc-pc-Configure-SPI-flash-boot-offset.patch
      ./roc-pc-config.patch
    ];
    postPatch =
      let
        setup_leds = "led green:work on; led red:diy on";
      in
    ''
      substituteInPlace include/tow-boot_env.h \
        --replace 'setup_leds=echo\0' 'setup_leds=${setup_leds}\0'
    '';
    SPISize = 128 /* Mbits */ * 1024 * 1024 / 8; # equiv to 16 MiB
  };
in
{
  libreComputer-amlS805xAc = amlogicGXL {
    boardIdentifier = "libreComputer-amlS805xAc";
    defconfig = "libretech-ac_defconfig";
    FIPDIR = "${amlogicFirmware}/lafrite";
    withSPI = true;
    SPISize = 128 /* Mbits */ * 1024 * 1024 / 8; # equiv to 16 MiB
  };
  libreComputer-rocRk3399Pc = rocRk3399Pc {
    defconfig = "roc-pc-rk3399_defconfig";
  };
  libreComputer-rocRk3399PcMezzanine = rocRk3399Pc {
    defconfig = "roc-pc-mezzanine-rk3399_defconfig";
  };
}
