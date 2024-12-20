# Scripts Repository

Welcome to the dmltbWM/scripts repository! This repository contains scripts for reinstalling from Debian systems to the latest stable version (Debian Stable), supporting Btrfs file system, and using systemd for time synchronization and network management.

#### Features
- Utilizes systemd-timesyncd for time synchronization
- Leverages systemd-networkd for network management

## Script Overview

### sim.sh

The `sim.sh` script allows you to reinstall from a Debian system to the latest Debian Stable version.


#### Parameters
- `--dhcp`: Enable DHCP functionality
- `--pwd <password>`: Set user password
- `--disk <disk>`: Set install disk,eg. /dev/sda
- `--mirror <mirror_url>`: Specify mirror source


#### Example Usage
```bash
apt update -y
bash <(wget -qO - 'https://raw.githubusercontent.com/dmltbWM/scripts/master/sim/sim.sh') --pwd sim@@@
```


### sim_rescue.sh
The `sim_rescue.sh` script allows you into rescue mode.you can relogin and do anything !

#### Parameters
- `--pwd <password>`: Set user password

#### Example Usage
```bash
apt update -y
bash <(wget -qO - 'https://raw.githubusercontent.com/dmltbWM/scripts/master/sim/sim_rescue.sh') --pwd sim@@@
```


## Contributing
We welcome any form of contributions! Please follow these steps:
1. **Fork** this repository.
2. Create a new branch (`git checkout -b feature/YourFeature`).
3. Commit your changes (`git commit -m 'Add some feature'`).
4. Push the changes to your branch (`git push origin feature/YourFeature`).
5. Submit a Pull Request.

Please ensure to follow our coding standards and provide clear descriptions when submitting.

## License

This project is licensed under the [ BSD 3 License](LICENSE). For more details, please refer to the license file.
