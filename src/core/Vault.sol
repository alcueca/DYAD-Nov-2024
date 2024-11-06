// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IVaultManager} from "../interfaces/IVaultManager.sol";
import {IDNft}         from "../interfaces/IDNft.sol";
import {IVault}        from "../interfaces/IVault.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

import {SafeCast}          from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeTransferLib}   from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20}             from "@solmate/src/tokens/ERC20.sol";

contract Vault is IVault {
  using SafeTransferLib   for ERC20;
  using SafeCast          for int;
  using FixedPointMathLib for uint;

  uint public constant STALE_DATA_TIMEOUT = 90 minutes; 

  IVaultManager public immutable vaultManager;
  ERC20         public immutable asset;
  IAggregatorV3 public immutable oracle;

  mapping(uint => uint) public id2asset;

  modifier onlyVaultManager() {
    if (msg.sender != address(vaultManager)) revert NotVaultManager();
    _;
  }

  constructor(
    IVaultManager _vaultManager,
    ERC20         _asset,
    IAggregatorV3 _oracle
  ) {
    vaultManager   = _vaultManager;
    asset          = _asset;
    oracle         = _oracle;
  }

  function deposit(
    uint id,
    uint amount
  )
    external 
      onlyVaultManager
  {
    id2asset[id] += amount; // @lead There is no transfer associated with this, or check that the id exists.
    emit Deposit(id, amount);
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

  function move(
    uint from,
    uint to,
    uint amount
  )
    external
      onlyVaultManager
  {
    id2asset[from] -= amount;
    id2asset[to]   += amount; // @info If from == to this is a no-op
    emit Move(from, to, amount);
  }

  // @info Return the value of the asset in USD
  function getUsdValue(
    uint id
  )
    external
    view 
    returns (uint) {
      return id2asset[id] * assetPrice() 
              * 1e18 
              / 10**oracle.decimals() // @lead The relevant oracles have 8 decimals
              / 10**asset.decimals(); // @lead weth and wstEth have 18 decimals
  }

  // @info Return the price of the asset in USD
  function assetPrice() // @lead asset price against USD?
    public 
    view 
    returns (uint) {
      (
        ,
        int256 answer,
        , 
        uint256 updatedAt, 
      ) = oracle.latestRoundData();
      if (block.timestamp > updatedAt + STALE_DATA_TIMEOUT) revert StaleData(); // @lead check heartbeat for tokens in scope, some might be longer than 90 minutes
      // @issue wstETH/USD has a heartbeat of 24h, so this will revert if there aren't price movements above 0.5%for more than 90m.
      return answer.toUint256();
  }
}
