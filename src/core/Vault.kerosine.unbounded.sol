// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {KerosineVault}        from "./Vault.kerosine.sol";
import {IVaultManager}        from "../interfaces/IVaultManager.sol";
import {Vault}                from "./Vault.sol";
import {Dyad}                 from "./Dyad.sol";
import {KerosineManager}      from "./KerosineManager.sol";
import {BoundedKerosineVault} from "./Vault.kerosine.bounded.sol";
import {KerosineDenominator}  from "../staking/KerosineDenominator.sol";

import {ERC20}           from "@solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";

import "forge-std/console2.sol";

contract UnboundedKerosineVault is KerosineVault {
  using SafeTransferLib for ERC20;

  Dyad                 public immutable dyad;
  KerosineDenominator  public kerosineDenominator;

  constructor(
      IVaultManager   _vaultManager,
      ERC20           _asset, 
      Dyad            _dyad, 
      KerosineManager _kerosineManager
  ) KerosineVault(_vaultManager, _asset, _kerosineManager) {
      dyad = _dyad;
  }

  function withdraw(
    uint    id,
    address to,
    uint    amount
  ) 
    external 
      onlyVaultManager
  {
    id2asset[id] -= amount;
    asset.safeTransfer(to, amount); 
    emit Withdraw(id, to, amount);
  }

  function setDenominator(KerosineDenominator _kerosineDenominator) 
    external 
      onlyOwner
  {
    kerosineDenominator = _kerosineDenominator; // @info bricked until this is set
  }

  function assetPrice() 
    public 
    view 
    override
    returns (uint) {
      uint tvl;
      address[] memory vaults = kerosineManager.getVaults(); // @info These would be the weth and wstETH vaults
      uint numberOfVaults = vaults.length;
      for (uint i = 0; i < numberOfVaults; i++) { // @info USD value of non-kerosine vaults
        Vault vault = Vault(vaults[i]);
        tvl += vault.asset().balanceOf(address(vault)) 
                * vault.assetPrice() * 1e18
                / (10**vault.asset().decimals()) 
                / (10**vault.oracle().decimals());
      } // @info This is an FP18
      uint numerator   = tvl - dyad.totalSupply(); // @reported H-01 There is a lot of DYAD minted for v1, while the TVL from the v1 collateral is not counted.
      uint denominator = kerosineDenominator.denominator(); // @info Circulating Kerosine supply
      return numerator * 1e8 / denominator; // @info 1e8 so that is consistent with other USD price feeds
  }
}