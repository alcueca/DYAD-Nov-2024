// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {DeployV2, Contracts} from "../../script/deploy/Deploy.V2.s.sol";

import {UnboundedKerosineVaultFixed} from "../../src/core/Vault.kerosine.unbounded.fixed.sol";

import {VaultManagerV2Fixed} from "../../src/core/VaultManagerV2Fixed.sol";
import {Vault} from "../../src/core/Vault.sol";
import {VaultWstEth} from "../../src/core/Vault.wsteth.sol";
import {UnboundedKerosineVault} from "../../src/core/Vault.kerosine.unbounded.sol";
import {DNft} from "../../src/core/DNft.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {Kerosine} from "../../src/staking/Kerosine.sol";
import {Licenser} from "../../src/core/Licenser.sol";
import {Parameters} from "../../src/params/Parameters.sol";

import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import "lib/solidity-stringutils/strings.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract V2Start is Test, Parameters, IERC721Receiver {
  using strings for *;

  function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }


  function depositedEth() 
    public 
    view
    returns (uint) {
      Vault ethVault = contracts.ethVault;
      return ERC20(ethVault.asset()).balanceOf(address(ethVault));
  }

  function depositedWstEth() public view returns (uint) {
      VaultWstEth wstEthVault = contracts.wstEth;
      return ERC20(wstEthVault.asset()).balanceOf(address(wstEthVault));
  }

  function depositedKerosine() public view returns (uint) {
      UnboundedKerosineVault kerosineVault = contracts.unboundedKerosineVault;
      return ERC20(kerosineVault.asset()).balanceOf(address(kerosineVault));
  }

  function getKerosineCirculatingSupply() public view returns (uint) {
      return ERC20(MAINNET_KEROSENE).totalSupply() - ERC20(MAINNET_KEROSENE).balanceOf(MAINNET_OWNER);
    }

  function mintedDyad() public view returns (uint) {
      return ERC20(MAINNET_DYAD).totalSupply() - dyadSupplyOutsideV2;
    }

  function ethToUsd(uint amount) public view returns (uint) {
    Vault ethVault = contracts.ethVault;
    IAggregatorV3 oracle = ethVault.oracle();
    ERC20 asset = ethVault.asset();
    return amount * ethVault.assetPrice() 
              * 1e8 
              / 10**oracle.decimals()
              / 10**asset.decimals();
  }

  function wstEthToUsd(uint amount) public view returns (uint) {
    VaultWstEth wstEthVault = contracts.wstEth;
    IAggregatorV3 oracle = wstEthVault.oracle();
    ERC20 asset = wstEthVault.asset();
    return amount * wstEthVault.assetPrice() 
              * 1e8 
              / 10**oracle.decimals()
              / 10**asset.decimals();
  }

  function dyadToUsd(uint amount) public view returns (uint) {
    return amount * 1e8 / 10**ERC20(MAINNET_DYAD).decimals();
  }

  function kerosineToUsd(uint amount) public view returns (uint) {
    // depositedEth(USD) + depositedWstEth(USD) - mintedDyad(USD) / kerosine circulating supply
    return (amount * (ethToUsd(depositedEth()) + wstEthToUsd(depositedWstEth()) - dyadToUsd(mintedDyad())) / getKerosineCirculatingSupply());
  }

  function globalCollateralization() public view returns (uint) {
    if (mintedDyad() == 0) return 1.5e18;
    return (1e18 * (ethToUsd(depositedEth()) + wstEthToUsd(depositedWstEth()))) / dyadToUsd(mintedDyad());
  }

  function displayDecimals(uint amount, uint decimals) public pure returns (string memory) {
    string memory integer = Strings.toString(amount / 10**decimals);
    string memory fractional = Strings.toString(amount % 10**decimals);
    while (fractional.toSlice().len() < decimals) fractional = "0".toSlice().concat(fractional.toSlice());
    return integer.toSlice().concat(",".toSlice()).toSlice().concat(fractional.toSlice());
  }

  function displayMetrics() public view {
    uint _depositedEth = depositedEth();
    uint _depositedWstEth = depositedWstEth();
    uint _depositedKerosine = depositedKerosine();
    uint _mintedDyad = mintedDyad();

    console2.log("------- GLOBAL ----------");
    console2.log("Deposited Eth:           %s", displayDecimals(_depositedEth, 18));
    console2.log("Deposited Eth(USD):      %s", displayDecimals(ethToUsd(_depositedEth),8));
    console2.log("Deposited WstEth:        %s", displayDecimals(_depositedWstEth, 18));
    console2.log("Deposited WstEth(USD):   %s", displayDecimals(wstEthToUsd(_depositedWstEth), 8));
    console2.log("Deposited Kerosine:      %s", displayDecimals(_depositedKerosine, 18));
    console2.log("Deposited Kerosine(USD): %s", displayDecimals(kerosineToUsd(_depositedKerosine), 8));
    console2.log("V2 minted Dyad:          %s", displayDecimals(_mintedDyad, 18));
    console2.log("V2 minted Dyad(USD):     %s", displayDecimals(dyadToUsd(_mintedDyad), 8));
    console2.log("Kerosine Circulating:    %s", displayDecimals(getKerosineCirculatingSupply(), 18));
    console2.log("Kerosine Price:          %s", displayDecimals(kerosineToUsd(1 ether), 8));
    console2.log("Global CR:               %s", displayDecimals(globalCollateralization(), 18));
    console2.log("------------------------");
  }

  function displayMetrics(uint id_) public view {
    uint _depositedEth = contracts.ethVault.id2asset(id_);
    uint _depositedWstEth = contracts.wstEth.id2asset(id_);
    uint _depositedKerosine = contracts.unboundedKerosineVault.id2asset(id_);
    uint _mintedDyad = dyad.mintedDyad(address(contracts.vaultManager), id_);

    console2.log("------------------------ %s", id_);
    console2.log("Deposited Eth:           %s", displayDecimals(_depositedEth, 18));
    console2.log("Deposited Eth(USD):      %s", displayDecimals(ethToUsd(_depositedEth),8));
    console2.log("Deposited WstEth:        %s", displayDecimals(_depositedWstEth, 18));
    console2.log("Deposited WstEth(USD):   %s", displayDecimals(wstEthToUsd(_depositedWstEth), 8));
    console2.log("Deposited Kerosine:      %s", displayDecimals(_depositedKerosine, 18));
    console2.log("Deposited Kerosine(USD): %s", displayDecimals(kerosineToUsd(_depositedKerosine), 8));
    console2.log("V2 minted Dyad:          %s", displayDecimals(_mintedDyad, 18));
    console2.log("V2 minted Dyad(USD):     %s", displayDecimals(dyadToUsd(_mintedDyad), 8));
    console2.log("Collateralization Ratio: %s", displayDecimals(contracts.vaultManager.collatRatio(id_), 18));
    console2.log("------------------------");
  }

  Contracts contracts;
  DNft dNft = DNft(MAINNET_DNFT);
  Dyad dyad = Dyad(MAINNET_DYAD);

  uint256 id;
  uint256 dyadSupplyOutsideV2;

  function setUp() public virtual {
    contracts = new DeployV2().run();

    dNft = DNft(MAINNET_DNFT);

    dyadSupplyOutsideV2 = ERC20(MAINNET_DYAD).totalSupply(); // @lead What happens if people burn or redeem dyad that was minted from v1?

    // TVL is zero
    // V2 minted Dyad is zero
    // Total collateralization level is undefined
    // Kerosene circulating amount is X
    // Kerosene value is zero
  }
}

contract PoCs is V2Start {

  function testAddKerosineVaultReverts() public {
    DNft dNft = DNft(MAINNET_DNFT);
    
    // We reset the DNft contract to be able to mint free DNfts
    vm.etch(address(MAINNET_DNFT), address(new DNft()).code);
    dNft = DNft(MAINNET_DNFT);

    uint id = dNft.mintNft(address(this));

    // Add a kerosene vault
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
  }

  function testMintWithKerosineReverts() public {
    // We license the vault manager to be able to mint DYAD
    vm.prank(MAINNET_OWNER);
    Licenser(contracts.vaultLicenser).add(address(contracts.vaultManager));

    DNft dNft = DNft(MAINNET_DNFT);
    
    // We reset the DNft contract to be able to mint free DNfts
    vm.etch(address(MAINNET_DNFT), address(new DNft()).code);
    dNft = DNft(MAINNET_DNFT);

    uint id = dNft.mintNft(address(this));

    // Obtain weth
    vm.prank(MAINNET_WETH); // deal not working for me
    ERC20(MAINNET_WETH).transfer(address(this), 1 ether);

    // Add the weth vault and deposit 1 eth    
    contracts.vaultManager.add(id, address(contracts.ethVault));
    ERC20(MAINNET_WETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.ethVault), 1 ether);

    // Move to the next block to pass the flash loan protection
    vm.roll(block.number + 1);

    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 100_000_000 ether); // This is a huge amount because the surplus collateral is low and the unitary price of kerosine is also low.

    // Add the kerosene vault and deposit kerosene
    contracts.vaultManager.add(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 100_000_000 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 100_000_000 ether);

    // Mint dyad, and watch it revert
    contracts.vaultManager.mintDyad(id, 1 ether, address(this));
  }

  function testMintWithOnlyKerosine() public {
    // We license the vault manager to be able to mint DYAD
    vm.prank(MAINNET_OWNER);
    Licenser(contracts.vaultLicenser).add(address(contracts.vaultManager));

    DNft dNft = DNft(MAINNET_DNFT);
    
    // We reset the DNft contract to be able to mint free DNfts
    vm.etch(address(MAINNET_DNFT), address(new DNft()).code);
    dNft = DNft(MAINNET_DNFT);

    // We patch the Unbounded Kerosine Vault so that it doesn't count the v1 DYAD
    vm.etch(
      address(contracts.unboundedKerosineVault),
      address(
        new UnboundedKerosineVaultFixed(
          contracts.vaultManager,
          Kerosine(MAINNET_KEROSENE), 
          Dyad    (MAINNET_DYAD),
          contracts.kerosineManager
        )
      ).code
    );

    uint id1 = dNft.mintNft(address(this)); // We will use this one to deposit some weth and give value to kerosine
    uint id2 = dNft.mintNft(address(this)); // We will use this one to mint some kerosine backed DYAD

    // Obtain weth
    vm.prank(MAINNET_WETH); // deal not working for me
    ERC20(MAINNET_WETH).transfer(address(this), 1 ether);

    // Add the weth vault and deposit 1 eth    
    contracts.vaultManager.add(id1, address(contracts.ethVault));
    ERC20(MAINNET_WETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id1, address(contracts.ethVault), 1 ether);

    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 100_000_000 ether); // This is a huge amount because the surplus collateral is low and the unitary price of kerosine is also low.

    // Add the kerosene vault and deposit 1 kerosene
    contracts.vaultManager.add(id2, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 100_000_000 ether);
    contracts.vaultManager.deposit(id2, address(contracts.unboundedKerosineVault), 100_000_000 ether);

    // Mint dyad
    contracts.vaultManager.mintDyad(id2, 1 ether, address(this));

    // Success!
    assertGt(ERC20(MAINNET_DYAD).balanceOf(address(this)), 0);
  }

  function testLiquidateButKerosine() public {
    // We license the vault manager to be able to mint DYAD
    vm.prank(MAINNET_OWNER);
    Licenser(contracts.vaultLicenser).add(address(contracts.vaultManager));

    DNft dNft = DNft(MAINNET_DNFT);
    

    // Add the vault manager to the OLD licenser to allow minting DYAD
    vm.prank(MAINNET_OWNER);
    Licenser(0xd8bA5e720Ddc7ccD24528b9BA3784708528d0B85).add(address(contracts.vaultManager));

    // We reset the DNft contract to be able to mint free DNfts
    vm.etch(address(MAINNET_DNFT), address(new DNft()).code);
    dNft = DNft(MAINNET_DNFT);

    uint id = dNft.mintNft(address(this));

    // We patch the Unbounded Kerosine Vault so that it doesn't count the v1 DYAD
    vm.etch(
      address(contracts.unboundedKerosineVault),
      address(
        new UnboundedKerosineVaultFixed(
          contracts.vaultManager,
          Kerosine(MAINNET_KEROSENE), 
          Dyad    (MAINNET_DYAD),
          contracts.kerosineManager
        )
      ).code
    );

    // We patch the VaultManager so that it uses the Licenser to decide on adding kerosene vaults to DNfts
    vm.etch(
      address(contracts.vaultManager),
      address(
        new VaultManagerV2Fixed(
        DNft(MAINNET_DNFT),
        Dyad(MAINNET_DYAD),
        contracts.vaultLicenser
      )
      ).code
    );

    // Obtain weth
    vm.prank(MAINNET_WETH); // deal not working for me
    ERC20(MAINNET_WETH).transfer(address(this), 1 ether);

    // Add the weth vault and deposit 1 eth    
    contracts.vaultManager.add(id, address(contracts.ethVault));
    ERC20(MAINNET_WETH).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.ethVault), 1 ether);

    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 1 ether); // This is a huge amount because the surplus collateral is low and the unitary price of kerosine is also low.

    // Add the kerosene vault and deposit kerosene
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 1 ether);

    // Mint dyad
    contracts.vaultManager.mintDyad(id, 1 ether, address(this));

      // Get a destination dNFT
    uint to = dNft.mintNft(address(this));

    // Unlicense the eth and wsteth vaults to drop the value of the victim's collateral to zero
    vm.startPrank(MAINNET_OWNER);
    contracts.vaultLicenser.remove(address(contracts.ethVault));
    contracts.vaultLicenser.remove(address(contracts.wstEth));
    vm.stopPrank();

    // Liquidate
    contracts.vaultManager.liquidate(id, to);

    // We still have the kerosine in the vault
    assertGt(contracts.unboundedKerosineVault.id2asset(id), 0);
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
    dNft = DNft(MAINNET_DNFT);
    
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

    displayMetrics();
  }
}

abstract contract V2WithDeposits is V2Start {
  function setUp() public virtual override{
    super.setUp();

    // FIX: Add the vault manager to the OLD licenser
    vm.prank(MAINNET_OWNER);
    Licenser(0xd8bA5e720Ddc7ccD24528b9BA3784708528d0B85).add(address(contracts.vaultManager));

    vm.etch(address(MAINNET_DNFT), address(new DNft()).code); // We reset the DNft contract to be able to mint free DNfts
    dNft = DNft(MAINNET_DNFT);
    
    id = dNft.mintNft(address(this));

    // We patch the VaultManager so that it uses the Licenser to decide on adding kerosene vaults to DNfts
    vm.etch(
      address(contracts.vaultManager),
      address(
        new VaultManagerV2Fixed(
        DNft(MAINNET_DNFT),
        Dyad(MAINNET_DYAD),
        contracts.vaultLicenser
      )
      ).code
    );

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

    // Move to the next block to pass the flash loan protection
    vm.roll(block.number + 1);
  }
}

contract V2WithDepositsTest is V2WithDeposits {
  function testWithdrawNonKerosine() public {
    // Withdraw 0.5 eth
    contracts.vaultManager.withdraw(id, address(contracts.ethVault), 0.5 ether, address(this));
  }

  function testMintDyad() public {
    // Mint dyad
    contracts.vaultManager.mintDyad(id, 1000 ether, address(this));

    displayMetrics();
  }

  function testDepositKerosine() public {
    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 100_000_000 ether);

    // Add the kerosene vault and deposit 1 kerosene
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 100_000_000 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 100_000_000 ether);

    displayMetrics();
  }
}

abstract contract V2WithKerosine is V2WithDeposits {
  function setUp() public virtual override {
    super.setUp();

    // We patch the Unbounded Kerosine Vault so that it doesn't count the v1 DYAD
    vm.etch(
      address(contracts.unboundedKerosineVault),
      address(
        new UnboundedKerosineVaultFixed(
          contracts.vaultManager,
          Kerosine(MAINNET_KEROSENE), 
          Dyad    (MAINNET_DYAD),
          contracts.kerosineManager
        )
      ).code
    );

    // Obtain kerosene
    vm.prank(MAINNET_OWNER);
    ERC20(MAINNET_KEROSENE).transfer(address(this), 1 ether);

    // Add the kerosene vault and deposit 1 kerosene
    contracts.vaultManager.addKerosene(id, address(contracts.unboundedKerosineVault));
    ERC20(MAINNET_KEROSENE).approve(address(contracts.vaultManager), 1 ether);
    contracts.vaultManager.deposit(id, address(contracts.unboundedKerosineVault), 1 ether);

    // Move to the next block to pass the flash loan protection
    vm.roll(block.number + 1);
  }
}

contract V2WithKerosineTest is V2WithKerosine {
  function testMintDyadWithKerosine() public {
    contracts.vaultManager.mintDyad(id, 1000 ether, address(this));

    displayMetrics();
  }

  function withdrawKerosine() public {
    contracts.vaultManager.withdraw(id, address(contracts.unboundedKerosineVault), 1 ether, address(this));
  }
}

abstract contract V2WithKerosineAndDyad is V2WithKerosine {
  function setUp() public virtual override {
    super.setUp();

    contracts.vaultManager.mintDyad(id, 1000 ether, address(this));
  }
}

contract V2WithKerosineAndDyadTest is V2WithKerosineAndDyad {
  function testBurnDyad() public {
    contracts.vaultManager.burnDyad(id, 1000 ether);
  }

  function testRedeemDyadFromNonKerosine() public {
    contracts.vaultManager.redeemDyad(id, address(contracts.ethVault), 1000 ether, address(this));
  }

  function testLiquidation() public {
    // Get a destination dNFT
    DNft dNft = DNft(MAINNET_DNFT);
    uint to = dNft.mintNft(address(this));

    // Unlicense the eth and wsteth vaults to drop the value of the victim's collateral to zero
    vm.startPrank(MAINNET_OWNER);
    contracts.vaultLicenser.remove(address(contracts.ethVault));
    contracts.vaultLicenser.remove(address(contracts.wstEth));
    vm.stopPrank();

    // Liquidate
    contracts.vaultManager.liquidate(id, to);
    
    displayMetrics(id);
    displayMetrics(to);
  }
}
