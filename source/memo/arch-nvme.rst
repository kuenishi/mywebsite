Arch Linux ops (NVMe SSD) 2025-04-19
------------------------------------

まず物理的に設置してカーネルに認識してもらう::

  [Sat Apr 19 09:54:08 2025] nvme nvme0: pci function 0000:01:00.0
  [Sat Apr 19 09:54:08 2025] nvme nvme0: D3 entry latency set to 10 seconds
  [Sat Apr 19 09:54:08 2025] nvme nvme0: 6/0/0 default/read/poll queues

実施時点での Linux はこれ::

  $ uname -a
  Linux ore-no-linux 6.14.2-arch1-1 #1 SMP PREEMPT_DYNAMIC Thu, 10 Apr 2025 18:43:59 +0000 x86_64 GNU/Linux

ついにわたしの村にもNVMeがきた！::

  $ ls /dev/nvme*
  /dev/nvme0  /dev/nvme0n1

つぎにNVMe操作用のツールをインストールする::

  $ paru -Ss nvme-cli
  extra/nvme-cli 2.12-1 [804.59 KiB 1.83 MiB]
      NVM-Express user space tooling for Linux
  aur/nvme-cli-git r2646.29c66608-1 [+5 ~0.00]
      NVM-Express user space tooling for Linux
  $ paru -S nvme-cli


そうすると見えるようになる::

  $ sudo nvme list
  Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev
  --------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
  /dev/nvme0n1          /dev/ng0n1            2(redacted)P         KIOXIA-EXCERIA PRO SSD                   0x1          2.00  TB /   2.00  TB    512   B +  0 B   EIFA10.3

まずはLBAF確認::

  $ sudo nvme id-ns /dev/nvme0n1 | tail
  nulbaf  : 0
  kpiodaag: 0
  anagrpid: 0
  nsattr  : 0
  nvmsetid: 0
  endgid  : 0
  nguid   : 8ce38e0300a91afb0000000000000000
  eui64   : 8ce38e0300a91afb
  lbaf  0 : ms:0   lbads:9  rp:0x2 (in use)
  lbaf  1 : ms:0   lbads:12 rp:0x1

まずこれを１にすると、ブロックサイズが 4KiB になって性能がちょっとよくなる::

  $ sudo nvme format -lbaf=1 /dev/nvme0n1
  You are about to format nvme0n1, namespace 0x1.
  WARNING: Format may irrevocably delete this device's data.
  You have 10 seconds to press Ctrl-C to cancel this operation.

  Use the force [--force] option to suppress this warning.
  Sending format operation ...
  Success formatting namespace:1
  $ sudo nvme list
  Node                  Generic               SN                   Model                                    Namespace  Usage         Format           FW Rev
  --------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
  /dev/nvme0n1          /dev/ng0n1            2(redacted)P         KIOXIA-EXCERIA PRO SSD                   0x1          2.00  TB /   2.00  TB      4 KiB +  0 B   EIFA10.3

ブート用なのでfat32 つくる::

  $ sudo parted /dev/nvme0n1 -s mklabel gpt -s mkpart ESP fat32 1MiB 513MiB -s set 1 boot on -s mkpart primary ext4 513MiB 100%
  $ sudo parted /dev/nvme0n1 print
  Model: KIOXIA-EXCERIA PRO SSD (nvme)
  Disk /dev/nvme0n1: 2000GB
  Sector size (logical/physical): 4096B/4096B
  Partition Table: gpt
  Disk Flags:

  Number  Start   End     Size    File system  Name     Flags
   1      1049kB  538MB   537MB   fat32        ESP      boot, esp
   2      538MB   2000GB  2000GB               primary

OS 入れる方は暗号化する。::

  $ sudo cryptsetup luksFormat /dev/nvme0n1p2

  WARNING!
  ========
  This will overwrite data on /dev/nvme0n1p2 irrevocably.

  Are you sure? (Type 'yes' in capital letters): YES
  Enter passphrase for /dev/nvme0n1p2:
  Verify passphrase:
  $ sudo cryptsetup open /dev/nvme0n1p2 crypt-root
  Enter passphrase for /dev/nvme0n1p2:
  $ sudo mkfs.btrfs -L root /dev/mapper/crypt-root
  btrfs-progs v6.14
  See https://btrfs.readthedocs.io for more information.

  Performing full device TRIM /dev/mapper/crypt-root (1.82TiB) ...
  NOTE: several default settings have changed in version 5.15, please make sure
        this does not affect your deployments:
        - DUP for metadata (-m dup)
        - enabled no-holes (-O no-holes)
        - enabled free-space-tree (-R free-space-tree)

  Label:              root
  UUID:               910ade79-dee0-494b-abbb-686bcc18815c
  Node size:          16384
  Sector size:        4096        (CPU page size: 4096)
  Filesystem size:    1.82TiB
  Block group profiles:
    Data:             single            8.00MiB
    Metadata:         DUP               1.00GiB
    System:           DUP               8.00MiB
  SSD detected:       yes
  Zoned device:       no
  Features:           extref, skinny-metadata, no-holes, free-space-tree
  Checksum:           crc32c
  Number of devices:  1
  Devices:
     ID        SIZE  PATH
      1     1.82TiB  /dev/mapper/crypt-root


なお2025年の時点では subvolume の暗号化は実装されていなそう。ZFSではできるのに・・・・

このあといろいろインストールして使えるようにした。::

  $ lsblk -f
  NAME           FSTYPE      FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
  sda
  └─sda1         btrfs             data  651e1d6c-7f93-42ba-8371-cbe536bf9341  759.4G    18% /data
  sdb
  ├─sdb1         vfat        FAT32       27C8-E845
  └─sdb2         ext4        1.0         82fef201-70d8-426e-b924-9d72e2251ef9
  sr0
  nvme0n1
  ├─nvme0n1p1    vfat        FAT32       A0CB-B05A                             319.5M    37% /boot
  └─nvme0n1p2    crypto_LUKS 2           b7c4fde1-ba33-42cf-8db1-62c1c372c11d
    └─crypt-root btrfs             root  910ade79-dee0-494b-abbb-686bcc18815c    1.1T    37% /



ちょっと工夫が必要だった点としては、 ``mkinitcpio.conf`` のHOOKSを以下のようにしたところ::

  HOOKS=(base systemd udev autodetect microcode modconf kms keyboard keymap consolefont sd-vconsole sd-encrypt block btrfs filesystems fsck)

  # Add btrfsck to binaries
  BINARIES=(btrfsck)

ふつうに encrypted root な btrfs を LUKS で作れるようになっていてなんか感動した。


参考
- https://github.com/raven2cz/geek-room/blob/main/arch-install-luks-btrfs/arch-install-luks-btrfs.md
- https://zenn.dev/archer/articles/2379e1ab40a117
