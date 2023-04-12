// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {AztecDistributor} from "../src/AztecDistributor.sol";
import {ERC4626Migrator} from "../src/ERC4626Migrator.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract AztecDistributorTest is Test {
    AztecDistributor public DISTRIBUTOR;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        DISTRIBUTOR = new AztecDistributor();

        vm.label(address(WETH), "WETH");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");
    }

    function testDistribute() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 709317925561782833751);
        deal(address(DAI), address(this), 327140818443534621219584 + 25215772580);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));

        // check constants
        assertEq(DISTRIBUTOR.eulerMultisig(), 0xcAD001c30E96765aC90307669d578219D4fb1DCe, "Euler Multisig");
        assertEq(DISTRIBUTOR.weweth4626(), 0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0, "weweth4626");
        assertEq(DISTRIBUTOR.wewsteth4626(), 0x60897720AA966452e8706e74296B018990aEc527, "wewsteth4626");
        assertEq(DISTRIBUTOR.wedai4626(), 0x4169Df1B7820702f566cc10938DA51F6F597d264, "wedai4626");

        // Distribute
        DISTRIBUTOR.distribute();

        // Check results
        address weweth4626Migrator = DISTRIBUTOR.weweth4626Migrator();
        address wewsteth626Migrator = DISTRIBUTOR.wewsteth4626Migrator();
        address wedai4626Migrator = DISTRIBUTOR.wedai4626Migrator();

        assertEq(WETH.balanceOf(weweth4626Migrator), 375853222858287897925, "WETH_weweth4626Migrator");
        assertEq(WETH.balanceOf(wewsteth626Migrator), 281939966842142630806, "WETH_wewsteth4626Migrator");
        assertEq(WETH.balanceOf(wedai4626Migrator), 5152473586135230502, "WETH_wedai4626Migrator");

        assertEq(DAI.balanceOf(weweth4626Migrator), 173345303296992109902679 + 13361327904000000000000, "DAI_weweth4626Migrator");
        assertEq(DAI.balanceOf(wewsteth626Migrator), 13003206063294082694104 + 10022775161000000000000, "DAI_wewsteth4626Migrator");
        assertEq(DAI.balanceOf(wedai4626Migrator), 23763454513601684375865 + 1831669515000000000000, "DAI_wedai4626Migrator");
        
        assertEq(USDC.balanceOf(weweth4626Migrator), 0, "USDC_weweth4626Migrator");
        assertEq(USDC.balanceOf(wewsteth626Migrator), 0, "USDC_wewsteth4626Migrator");
        assertEq(USDC.balanceOf(wedai4626Migrator), 0, "USDC_wedai4626Migrator");
    }

    function testDistributeWETHTransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 709317925561782833750);
        deal(address(DAI), address(this), 327140818443534621219584 + 25215772580);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("WETH balance incorrect");
        DISTRIBUTOR.distribute();
    }

    function testDistributeDAITransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 709317925561782833751);
        deal(address(DAI), address(this), 327140818443534621219584 + 25215772580 - 1);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("DAI balance incorrect");
        DISTRIBUTOR.distribute();
    }

    function testDistributeUSDCTransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 709317925561782833751);
        deal(address(DAI), address(this), 327140818443534621219584 + 25215772580);
        deal(address(USDC), address(this), 1);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("USDC balance incorrect");
        DISTRIBUTOR.distribute();
    }
}
