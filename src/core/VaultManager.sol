// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {DNft}          from "./DNft.sol";
import {Dyad}          from "./Dyad.sol";
import {Licenser}      from "./Licenser.sol";
import {Vault}         from "./Vault.sol";
import {IVaultManager} from "../interfaces/IVaultManager.sol";

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20}             from "@solmate/src/tokens/ERC20.sol";
import {SafeTransferLib}   from "@solmate/src/utils/SafeTransferLib.sol";
import {EnumerableSet}     from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract VaultManager is IVaultManager {
  using EnumerableSet     for EnumerableSet.AddressSet;
  using FixedPointMathLib for uint;
  using SafeTransferLib   for ERC20;

  uint public constant MAX_VAULTS                = 5;
  uint public constant MIN_COLLATERIZATION_RATIO = 1.5e18; // 150%
  uint public constant LIQUIDATION_REWARD        = 0.2e18; //  20%

  DNft     public immutable dNft;
  Dyad     public immutable dyad;
  Licenser public immutable vaultLicenser;

  mapping (uint => EnumerableSet.AddressSet) internal vaults; 

  modifier isDNftOwner(uint id) {
    if (dNft.ownerOf(id) != msg.sender)   revert NotOwner();    _;
  }
  modifier isValidDNft(uint id) {
    if (dNft.ownerOf(id) == address(0))   revert InvalidDNft(); _;
  }
  modifier isLicensed(address vault) {
    if (!vaultLicenser.isLicensed(vault)) revert NotLicensed(); _;
  }

  constructor(
    DNft     _dNft,
    Dyad     _dyad,
    Licenser _licenser
  ) {
    dNft          = _dNft;
    dyad          = _dyad;
    vaultLicenser = _licenser;
  }

  function add(
      uint    id,
      address vault
  ) 
    external
      isDNftOwner(id)
  {
    if (vaults[id].length() >= MAX_VAULTS) revert TooManyVaults();
    if (!vaultLicenser.isLicensed(vault))  revert VaultNotLicensed();
    if (!vaults[id].add(vault))            revert VaultAlreadyAdded();
    emit Added(id, vault);
  }

  function remove(
      uint    id,
      address vault
  ) 
    external
      isDNftOwner(id)
  {
    if (Vault(vault).id2asset(id) > 0) revert VaultHasAssets();
    if (!vaults[id].remove(vault))     revert VaultNotAdded();
    emit Removed(id, vault);
  }

  function deposit(
    uint    id,
    address vault,
    uint    amount
  ) 
    external 
      isValidDNft(id) 
  {
    Vault _vault = Vault(vault);
    _vault.asset().safeTransferFrom(msg.sender, address(vault), amount);
    _vault.deposit(id, amount);
  }

  function withdraw(
    uint    id,
    address vault,
    uint    amount,
    address to
  ) 
    public 
      isDNftOwner(id)
  {
    Vault(vault).withdraw(id, to, amount);
    if (collatRatio(id) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
  }

  function mintDyad(
    uint    id,
    uint    amount,
    address to
  )
    external 
      isDNftOwner(id)
  {
    dyad.mint(id, to, amount);
    if (collatRatio(id) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
    emit MintDyad(id, amount, to);
  }

  function burnDyad(
    uint id,
    uint amount
  ) 
    external 
      isValidDNft(id)
  {
    dyad.burn(id, msg.sender, amount);
    emit BurnDyad(id, amount, msg.sender);
  }

  // @info Redeem Dyad at $1 for the underlying asset
  function redeemDyad(
    uint    id,
    address vault,
    uint    amount,
    address to
  )
    external 
      isDNftOwner(id)
    returns (uint) { 
      dyad.burn(id, msg.sender, amount);
      Vault _vault = Vault(vault);
      uint asset = amount 
                    * (10**(_vault.oracle().decimals() + _vault.asset().decimals())) 
                    / _vault.assetPrice() 
                    / 1e18; // @info Convert the amount of Dyad/USD to the amount of the underlying asset
      withdraw(id, vault, asset, to);
      emit RedeemDyad(id, vault, amount, to);
      return asset;
  }

  function liquidate(
    uint id,
    uint to
  ) 
    external 
      isValidDNft(id)
      isValidDNft(to)
    {
      uint cr = collatRatio(id);
      if (cr >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh();
      dyad.burn(id, msg.sender, dyad.mintedDyad(address(this), id)); // @info The liquidator burns Dyad to cancel all of the dNFT's debt

      uint cappedCr               = cr < 1e18 ? 1e18 : cr; // @info If the CR is less than 100%, it is set to 100% // @lead What would actually happen then?
      uint liquidationEquityShare = (cappedCr - 1e18).mulWadDown(LIQUIDATION_REWARD);
      uint liquidationAssetShare  = (liquidationEquityShare + 1e18).divWadDown(cappedCr);

      uint numberOfVaults = vaults[id].length();
      for (uint i = 0; i < numberOfVaults; i++) { // @info With the debt cleared up, we move the collateral to the user
          Vault vault      = Vault(vaults[id].at(i)); // @lead Does the line below reverse the math to move 100 + cr_surplus * reward of the collateral?
          uint  collateral = vault.id2asset(id).mulWadUp(liquidationAssetShare); // @lead What does rounding up here mean?
          vault.move(id, to, collateral); // @lead If a user liquidates itself (id == to) 
      }
      emit Liquidate(id, msg.sender, to);
  }

  function collatRatio(
    uint id
  )
    public 
    view
    returns (uint) {
      uint _dyad = dyad.mintedDyad(address(this), id); // @lead If the VaultManager changes, debt for each dNFT is reduced to zero, and the CR is infinite.
      if (_dyad == 0) return type(uint).max;
      return getTotalUsdValue(id).divWadDown(_dyad);
  }

  function getTotalUsdValue(
    uint id
  ) 
    public 
    view
    returns (uint) {
      uint totalUsdValue;
      uint numberOfVaults = vaults[id].length(); 
      for (uint i = 0; i < numberOfVaults; i++) { // @lead If there would be a chance to reenter, we might be able to reorder the vaults and alter the count
        Vault vault = Vault(vaults[id].at(i)); // @info get the vault for dNFT `id` at position `i`
        uint usdValue;
        if (vaultLicenser.isLicensed(address(vault))) { // @lead Governance unlicensing a vault would send many into liquidation
          usdValue = vault.getUsdValue(id);        
        }
        totalUsdValue += usdValue;
      }
      return totalUsdValue;
  }

  // ----------------- MISC ----------------- //

  function getVaults(
    uint id
  ) 
    external 
    view 
    returns (address[] memory) {
      return vaults[id].values();
  }

  function hasVault(
    uint    id,
    address vault
  ) 
    external 
    view 
    returns (bool) {
      return vaults[id].contains(vault);
  }
}
