{ stdenvNoCC, lib
, imageBuilder
, utillinux
}:

/*  */ let scope = { "diskImage.makeMBR" =

let
  inherit (lib) concatMapStringsSep optionalString;

  # List of known mappings of MBR partition types to filesystems.
  types = {
    "FAT32" =  "b";
    "ESP"   = "ef";
    "ext2"  = "83";
    "ext3"  = "83";
    "ext4"  = "83";
    "EBBR-firmware" = "93";
  };
in
{
  name
  , partitions
  # Without the prefixed `0x`
  , diskID
  , postBuild ? ""
  # Default alignment at 1MiB
  , alignment ? imageBuilder.size.MiB 1
  , sectorSize ? 512
}:

let
  alignment' = alignment;
  sectorSize' = sectorSize;
in

let
  _name = name;

  eachPart = partitions: fn: (
    concatMapStringsSep "\n" (partition:
      fn partition
  ) partitions);

  alignment = toString alignment';
  sectorSize = toString sectorSize';

  image = partition: 
    if lib.isDerivation partition then
      "${partition}/${partition.filename}"
    else
      partition.filename
  ;
in
stdenvNoCC.mkDerivation rec {
  name = "disk-image-${_name}";
  filename = "${_name}.img";
  img = "${placeholder "out"}/${filename}";

  nativeBuildInputs = [
    utillinux
  ];

  buildCommand = let
    # This fragment is used to compute the (aligned) size of the partition.
    # It is used *only* to track the tally of the space used, thus the starting
    # offset of the next partition. The filesystem sizes are untouched.
    sizeFragment = partition: ''
      # If a partition asks to start at a specific offset, restart tally at
      # that location.
      ${optionalString (partition ? offset) ''
        offset=$((${toString partition.offset}))

        if (( offset < totalSize )); then
          echo "Partition wanted to start at $offset while we were already at $totalSize"
          echo "As of right now, partitions need to be in order."
          exit 1
        else
          totalSize=$offset
        fi
      ''}
      start=$totalSize
      ${
        if partition ? length then
        ''size=$((${toString partition.length}))''
        else
        ''size=$(($(du --apparent-size -B 512 "$input_img" | awk '{ print $1 }') * 512))''
      }
      size=$(( $(if (($size % ${alignment})); then echo 1; else echo 0; fi ) + size / ${alignment} ))
      size=$(( size * ${alignment} ))
      totalSize=$(( totalSize + size ))
      echo "Partition: start $start | size $size | totalSize $totalSize"
    '';

    # This fragment is used to add the desired gap to `totalSize`.
    # We're setting `start` and `size` only to mirror the information shown
    # for partitions.
    # Do note that gaps are always aligned, so two gaps sized half the alignment
    # would create 2× the space expected.
    # What may *instead* be done at one point is always align `start` for partitions.
    gapFragment = partition: ''
      start=$totalSize
      size=${toString partition.length}
      size=$(( $(if (($size % ${alignment})); then echo 1; else echo 0; fi ) + size / ${alignment} ))
      size=$(( size * ${alignment} ))
      totalSize=$(( totalSize + size ))
      echo "Gap: start $start | size $size | totalSize $totalSize"
    '';
  in ''
    mkdir -p $out

    cat <<EOF > script.sfdisk
    label: dos
    grain: ${alignment}
    sector-size: ${sectorSize}
    label-id: 0x${diskID}
    EOF

    totalSize=${alignment}
    echo
    echo "Gathering information about partitions."
    ${eachPart partitions (partition:
      if partition ? isGap && partition.isGap then
        (gapFragment partition)
      else
        ''
          input_img="${image partition}"
          ${sizeFragment partition}
          echo " -> ${partition.name}: $size / ${partition.filesystemType}"

          (
          # The size is /1024; otherwise it's in sectors.
          echo -n 'start='"$((start/${sectorSize}))"
          echo -n ', size='"$((size/${sectorSize}))"
          echo -n ', type=${types."${partition.filesystemType}"}'
          ${optionalString (partition ? bootable && partition.bootable)
              "echo -n ', bootable'"}
          echo "" # Finishes the command
          ) >> script.sfdisk
        ''
    )}

    echo "--- script ----"
    cat script.sfdisk
    echo "--- script ----"

    echo
    echo "Making image, $totalSize bytes..."
    truncate -s $((totalSize)) $img
    sfdisk $img < script.sfdisk

    totalSize=${alignment}
    echo
    echo "Writing partitions into image"
    ${eachPart partitions (partition: 
      if partition ? isGap && partition.isGap then
        (gapFragment partition)
      else
        ''
          input_img="${image partition}"
          ${sizeFragment partition}
          echo " -> ${partition.name}: $size / ${partition.filesystemType}"

          echo "$start / $size"
          dd conv=notrunc if=$input_img of=$img seek=$((start/512)) count=$((size/512)) bs=512
        ''
    )}

    echo
    echo "Information about the image:"
    ls -lh $img
    sfdisk -V --list $img
    ${postBuild}
  '';
}

/*  */ ;}; in scope."diskImage.makeMBR"
