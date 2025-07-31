#!/bin/bash

set -eu

deploydir=$1


if [ -f ${IGconf_image_outputdir}/genimage.cfg ] ; then
   fstabs=()
   opts=()
   fstabs+=("${IGconf_image_outputdir}"/fstab*)
   for f in "${fstabs[@]}" ; do
      if [ -f "$f" ] ; then
         opts+=('-f' $f)
      fi
   done

   if [ -f ${IGconf_image_outputdir}/provisionmap.json ] ; then
      opts+=('-m' ${IGconf_image_outputdir}/provisionmap.json)
   fi
   image2json -g ${IGconf_image_outputdir}/genimage.cfg "${opts[@]}" > ${IGconf_image_outputdir}/image.json
fi


files=()

for f in "${IGconf_image_outputdir}/${IGconf_image_name}"*.${IGconf_image_suffix} ; do
   files+=($f)
   [[ -f "$f" ]] || continue

   # Ensure that the output image is a multiple of the selected sector size
   truncate -s %${IGconf_device_sector_size} $f
done

files+=("${IGconf_image_outputdir}/${IGconf_image_name}"*.${IGconf_image_suffix}.sparse)
files+=("${IGconf_image_outputdir}/${IGconf_image_name}"*.sbom)

msg "Deploying image and SBOM"

for f in "${files[@]}" ; do
   [[ -f "$f" ]] || continue
   case ${IGconf_image_compression} in
      zstd)
         zstd -v -f $f --sparse --output-dir-flat $deploydir
         ;;
      none)
         install -v -D -m 644 $f $deploydir
         ;;
      *)
         ;;
   esac
done
