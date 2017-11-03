function setTilesUpgradePipelines() {
  foundation="${1}"
  foundation_name="${2}"

  set +e
  grep "BoM_tile_" $foundation | grep "^[^#;]" > ./listOfEnabledTiles.txt
  set -e

  gatedApplyChangesJob=$(grep "gated-Apply-Changes-Job" $foundation | cut -d ":" -f 2 | tr -d " ")
  # if pivotal-releases-source is "s3", then later on avoid adding a duplicate maestro resource to the pipelines
  pivotalReleasesSource=$(grep "pivotal-releases-source" ./common/credentials.yml | grep "^[^#;]" | cut -d ":" -f 2 | tr -d " ")

  cat ./listOfEnabledTiles.txt | while read tileEntry
  do
    tileEntryKey=$(echo "$tileEntry" | cut -d ":" -f 1 | tr -d " ")
    tileEntryValue=$(echo "$tileEntry" | cut -d ":" -f 2 | tr -d " ")
    tile_name=$(echo "$tileEntryKey" | cut -d "_" -f 3)
    tileMetadataFilename="./common/pcf-tiles/$tile_name.yml"
    resource_name=$(grep "resource_name" $tileMetadataFilename | cut -d ":" -f 2 | tr -d " ")

    tile_globs=$(grep "globs" $tileMetadataFilename | cut -d ":" -f 2 | tr -d " ")
    [ -z "${tile_globs}" ] && tile_globs="\"*pivotal\""

    # update globs param for the tile resource
    cp ./operations/opsfiles/tile-globs-update.yml ./tile-globs-update-tmp.yml
    sed -i "s/GLOBS/$tile_globs/g" ./tile-globs-update-tmp.yml
    # Pipeline template file ./upgrade-tile-template.yml is produced by processPipelinePatchesPerFoundation() in ./operations/operations.sh
    cat ./upgrade-tile-template.yml | yaml_patch_linux -o ./tile-globs-update-tmp.yml > ./upgrade-tile-with-globs.yml

    cp ./upgrade-tile-with-globs.yml ./upgrade-tile.yml
    # update when tile template contains variables to be replaced with sed, e.g. releases in S3 bucket
    sed -i "s/RESOURCENAME/$resource_name/g" ./upgrade-tile.yml
    sed -i "s/PRODUCTVERSION/$tileEntryValue/g" ./upgrade-tile.yml

    # customize upgrade tile job name
    sed -i "s/\bupgrade-tile\b/upgrade-$tile_name-tile/g" ./upgrade-tile.yml
    sed -i "s/name: tile/name: $resource_name/g" ./upgrade-tile.yml
    sed -i "s/get: tile/get: $resource_name/g" ./upgrade-tile.yml
    sed -i "s/resource: tile/resource: $resource_name/g" ./upgrade-tile.yml

    if [ "${gatedApplyChangesJob,,}" == "true" ]; then
        sed -i "s/RESOURCE_NAME_GOES_HERE/$resource_name/g" ./upgrade-tile.yml
        sed -i "s/PREVIOUS_JOB_NAME_GOES_HERE/upgrade-$tile_name-tile/g" ./upgrade-tile.yml
    fi

    if [ "${pivotalReleasesSource,,}" == "pivnet" ]; then  # && [ "${gatedApplyChangesJob,,}" == "false" ];

        echo "Default pipeline, not adding resource for pcf-pipelines-maestro"
    else
        applyMaestroResourcePatch ./upgrade-tile.yml
    fi

    echo "Setting upgrade pipeline for tile [$tile_name], version [$tileEntryValue]"
    ./fly -t $foundation_name set-pipeline -p "$foundation_name-Upgrade-$tile_name" -c ./upgrade-tile.yml -l "./common/pcf-tiles/$tile_name.yml" -l ./common/credentials.yml -l "$foundation" -v "product_version_regex=${tileEntryValue}" -n
  done

}
