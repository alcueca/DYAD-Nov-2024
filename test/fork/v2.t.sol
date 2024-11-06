// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {DeployV2, Contracts} from "../../script/deploy/Deploy.V2.s.sol";

import {DNft} from "../../src/core/DNft.sol";
import {Licenser} from "../../src/core/Licenser.sol";
import {Parameters} from "../../src/params/Parameters.sol";

import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
abstract contract V2Start is Test, Parameters, IERC721Receiver {

  function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  Contracts contracts;
  uint256 id;

  function setUp() public virtual {
    contracts = new DeployV2().run();
  }
}

contract V2StartTest is V2Start {

  function testLicenseVaultManager() public {
    Licenser licenser = Licenser(MAINNET_VAULT_MANAGER_LICENSER);
    vm.prank(MAINNET_OWNER);
    licenser.add(address(contracts.vaultManager));
  }

  function testLicenseVaults() public {
    vm.prank(MAINNET_OWNER);
    contracts.vaultLicenser.add(address(contracts.ethVault));
    vm.prank(MAINNET_OWNER);
    contracts.vaultLicenser.add(address(contracts.wstEth));
    vm.prank(MAINNET_OWNER);
    contracts.vaultLicenser.add(address(contracts.unboundedKerosineVault));
    vm.prank(MAINNET_OWNER);
    contracts.vaultLicenser.add(address(contracts.boundedKerosineVault));
  }

  function testKeroseneVaults() public {
    address[] memory vaults = contracts.kerosineManager.getVaults();
    assertEq(vaults.length, 2);
    assertEq(vaults[0], address(contracts.ethVault));
    assertEq(vaults[1], address(contracts.wstEth));
  }

  function testOwnership() public {
    assertEq(contracts.kerosineManager.owner(),        MAINNET_OWNER);
    assertEq(contracts.vaultLicenser.owner(),          MAINNET_OWNER);
    assertEq(contracts.kerosineManager.owner(),        MAINNET_OWNER);
    assertEq(contracts.unboundedKerosineVault.owner(), MAINNET_OWNER);
    assertEq(contracts.boundedKerosineVault.owner(),   MAINNET_OWNER);
  }

  function testDenominator() public {
    uint denominator = contracts.kerosineDenominator.denominator();
    assertTrue(denominator < contracts.kerosene.balanceOf(MAINNET_OWNER));
  }

  function testDepositNonKerosine() public {
    vm.etch(address(MAINNET_DNFT), address(new DNft()).code); // We reset the DNft contract to be able to mint free DNfts
    DNft dNft = DNft(MAINNET_DNFT);
    // uint price = dNft.START_PRICE() + (dNft.PRICE_INCREASE() * (dNft.publicMints() + 1));
    // vm.deal(address(this), price);
    
    id = dNft.mintNft(address(this));

    // Obtain weth
    vm.prank(MAINNET_WETH); // deal not working
    ERC20(MAINNET_WETH).transfer(address(this), 1 ether);

    // Add the weth vault and deposit 1 eth    
    contracts.vaultManager.add(id, address(contracts.ethVault));
    ERC20(MAINNET_WETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.ethVault), 1 ether);

    // Obtain wsteth
    vm.prank(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);
    ERC20(MAINNET_WSTETH).transfer(address(this), 1 ether);

    // Add the wsteth vault and deposit 1 wsteth
    contracts.vaultManager.add(id, address(contracts.wstEth));
    ERC20(MAINNET_WSTETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.wstEth), 1 ether);
  }
}

abstract contract V2WithDeposits is V2Start {
  function setUp() public virtual override{
    super.setUp();

    vm.etch(address(MAINNET_DNFT), address(new DNft()).code); // We reset the DNft contract to be able to mint free DNfts
    DNft dNft = DNft(MAINNET_DNFT);
    
    id = dNft.mintNft(address(this));

    // Obtain weth
    vm.prank(MAINNET_WETH); // deal not working
    ERC20(MAINNET_WETH).transfer(address(this), 1 ether);

    // Add the weth vault and deposit 1 eth    
    contracts.vaultManager.add(id, address(contracts.ethVault));
    ERC20(MAINNET_WETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.ethVault), 1 ether);

    // Obtain wsteth
    vm.prank(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);
    ERC20(MAINNET_WSTETH).transfer(address(this), 1 ether);

    // Add the wsteth vault and deposit 1 wsteth
    contracts.vaultManager.add(id, address(contracts.wstEth));
    ERC20(MAINNET_WSTETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.wstEth), 1 ether);
  }
}

contract V2WithDepositsTest is V2WithDeposits {
  function testWithdrawNonKerosine() public {
    // Withdraw 0.5 eth
    vm.roll(block.number + 1);
    contracts.vaultManager.withdraw(id, address(contracts.ethVault), 0.5 ether, address(this));
  }

  function testMintDyad() public {
    // FIX: Add the vault manager to the OLD licenser
    vm.prank(MAINNET_OWNER);
    Licenser(0xd8bA5e720Ddc7ccD24528b9BA3784708528d0B85).add(address(contracts.vaultManager));

    // Mint dyad
    contracts.vaultManager.mintDyad(id, 1000 ether, address(this));
  }

  function testDepositKerosine() public {
    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 1 ether);

    // Add the kerosene vault and deposit 1 kerosene
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 1 ether);
  }
}

abstract contract V2WithKerosine is V2WithDeposits {
  function setUp() public virtual override{
    super.setUp();

    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 1 ether);

    // Add the kerosene vault and deposit 1 kerosene
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 1 ether);
  }
}

contract V2WithKerosineTest is V2WithKerosine {
  function testMintDyad() public {
    contracts.vaultManager.mintDyad(id, 1000 ether, address(this));
  }

  function withdrawKerosine() public {
    contracts.vaultManager.withdraw(id, address(contracts.unboundedKerosineVault), 1 ether, address(this));
  }
}
