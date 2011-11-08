#! /bin/sh -e

revision=$(svnversion "$NIXOS")
echo "NixOS revision is $revision"

buildAndUploadFor() {
    system="$1"
    arch="$2"

    echo "building $system image..."
    NIXOS_CONFIG=$NIXOS/modules/virtualisation/amazon-config.nix nix-build "$NIXOS" \
        -A config.system.build.amazonImage --argstr system "$system" -o ec2-ami

    ec2-bundle-image -i ./ec2-ami/nixos.img --user "$AWS_ACCOUNT" --arch "$arch" \
        -c "$EC2_CERT" -k "$EC2_PRIVATE_KEY"

    for region in eu-west-1 us-east-1 us-west-1; do
        echo "uploading $system image for $region..."

        name="$(echo nixos-$arch-r$revision | tr '[A-Z]_' '[a-z]-')"

        bucket="$name-$region"

        ec2-upload-bundle -b "$bucket" -m /tmp/nixos.img.manifest.xml \
            -a "$AWS_ACCESS_KEY_ID" -s "$AWS_SECRET_ACCESS_KEY" --location "$region"

        kernel=$(ec2-describe-images -o amazon --filter "manifest-location=*pv-grub-hd0_1.02-$arch*" --region "$region" | cut -f 2)
        echo "using PV-GRUB kernel $kernel"

        ami=$(ec2-register "$bucket/nixos.img.manifest.xml" -n "$name" -d "NixOS $system r$revision" \
            --region "$region" --kernel "$kernel" | cut -f 2)

        echo "AMI ID is $ami"

        echo "$system" "$region" "$ami" >> amis

        ec2-modify-image-attribute --region "$region" "$ami" -l -a all
    done
}

#buildAndUploadFor i686-linux i386
buildAndUploadFor x86_64-linux x86_64
