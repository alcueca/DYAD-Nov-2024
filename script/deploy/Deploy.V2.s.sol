// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/Script.sol";

import {Parameters}             from "../../src/params/Parameters.sol";
import {VaultManagerV2}         from "../../src/core/VaultManagerV2.sol";
import {DNft}                   from "../../src/core/DNft.sol";
import {Dyad}                   from "../../src/core/Dyad.sol";
import {Licenser}               from "../../src/core/Licenser.sol";
import {Vault}                  from "../../src/core/Vault.sol";
import {VaultWstEth}            from "../../src/core/Vault.wsteth.sol";
import {IWETH}                  from "../../src/interfaces/IWETH.sol";
import {IAggregatorV3}          from "../../src/interfaces/IAggregatorV3.sol";
import {KerosineManager}        from "../../src/core/KerosineManager.sol";
import {UnboundedKerosineVault} from "../../src/core/Vault.kerosine.unbounded.sol";
import {BoundedKerosineVault}   from "../../src/core/Vault.kerosine.bounded.sol";
import {Kerosine}               from "../../src/staking/Kerosine.sol";
import {KerosineDenominator}    from "../../src/staking/KerosineDenominator.sol";

import {ERC20} from "@solmate/src/tokens/ERC20.sol";

struct Contracts {
  Kerosine               kerosene;
  Licenser               vaultLicenser;
  VaultManagerV2         vaultManager;
  Vault                  ethVault;
  VaultWstEth            wstEth;
  KerosineManager        kerosineManager;
  UnboundedKerosineVault unboundedKerosineVault;
  BoundedKerosineVault   boundedKerosineVault;
  KerosineDenominator    kerosineDenominator;
}

contract DeployV2 is Script, Parameters {
  function run() public returns (Contracts memory) {
    vm.startBroadcast();  // ----------------------

    Licenser vaultLicenser = new Licenser();

    // Vault Manager needs to be licensed through the Vault Manager Licenser
    VaultManagerV2 vaultManager = new VaultManagerV2(
      DNft(MAINNET_DNFT),
      Dyad(MAINNET_DYAD),
      vaultLicenser
    ); // @issue vaultManager needs to be licensed on the old licenser at 0xd8bA5e720Ddc7ccD24528b9BA3784708528d0B85 for Dyad to allow minting.

    // weth vault
    Vault ethVault = new Vault(
      vaultManager,
      ERC20        (MAINNET_WETH),
      IAggregatorV3(MAINNET_WETH_ORACLE)
    );

    // wsteth vault
    VaultWstEth wstEth = new VaultWstEth(
      vaultManager, 
      ERC20        (MAINNET_WSTETH), 
      IAggregatorV3(MAINNET_CHAINLINK_STETH) // @info The vaults converts from stETH to wstETH
    );

    KerosineManager kerosineManager = new KerosineManager();

    kerosineManager.add(address(ethVault));
    kerosineManager.add(address(wstEth));

    vaultManager.setKeroseneManager(kerosineManager);

    kerosineManager.transferOwnership(MAINNET_OWNER);

    UnboundedKerosineVault unboundedKerosineVault = new UnboundedKerosineVault(
      vaultManager,
      Kerosine(MAINNET_KEROSENE), 
      Dyad    (MAINNET_DYAD),
      kerosineManager
    );

    BoundedKerosineVault boundedKerosineVault     = new BoundedKerosineVault(
      vaultManager,
      Kerosine(MAINNET_KEROSENE), 
      kerosineManager
    );

    KerosineDenominator kerosineDenominator       = new KerosineDenominator(
      Kerosine(MAINNET_KEROSENE)
    );

    unboundedKerosineVault.setDenominator(kerosineDenominator);

    unboundedKerosineVault.transferOwnership(MAINNET_OWNER);
    boundedKerosineVault.  transferOwnership(MAINNET_OWNER);

    vaultLicenser.add(address(ethVault));
    vaultLicenser.add(address(wstEth));
    vaultLicenser.add(address(unboundedKerosineVault)); // @reported H-02 The unboundedKerosineVault should be licensed to the KerosineManager. Because Kerosene can be added as a non-kerosene collateral, we can break things
    // vaultLicenser.add(address(boundedKerosineVault));

    vaultLicenser.transferOwnership(MAINNET_OWNER);

    vm.stopBroadcast();  // ----------------------------

    return Contracts(
      Kerosine(MAINNET_KEROSENE),
      vaultLicenser,
      vaultManager,
      ethVault,
      wstEth,
      kerosineManager,
      unboundedKerosineVault,
      boundedKerosineVault,
      kerosineDenominator
    );
  }
}
