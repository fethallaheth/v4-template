// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MyHook} from "../src/MyHook.sol";

contract MyHookTest is Test, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    MyHook public hook;
    IPoolManager public poolManager;
    address public constant ETH = address(0);
    address public constant TOKEN = address(1);
    address public constant USER = address(0x123);

    function setUp() public {
        poolManager = IPoolManager(address(0xABC)); // Mock address
        hook = new MyHook(poolManager);
    }

    function test_HookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeSwap);
        assertFalse(permissions.beforeAddLiquidity);
    }

    function test_AfterSwap_BuyToken() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(ETH),
            currency1: Currency.wrap(TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Simulate spending 1 ETH
        BalanceDelta delta = BalanceDelta.wrap(-1 ether, 1000e18); // -1 ETH, +1000 TOKEN
        bytes memory hookData = abi.encode(USER);

        // Test swap params (buying TOKEN with ETH)
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1 ether,
            sqrtPriceLimitX96: 0
        });

        hook.afterSwap(address(this), key, params, delta, hookData);
        
        // Should receive 0.2 POINTS for 1 ETH
        assertEq(hook.balanceOf(USER), 0.2 ether);
    }

    function test_AfterAddLiquidity() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(ETH),
            currency1: Currency.wrap(TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Simulate adding 1 ETH worth of liquidity
        BalanceDelta delta = BalanceDelta.wrap(-1 ether, -1000e18);
        bytes memory hookData = abi.encode(USER);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -1000,
            tickUpper: 1000,
            liquidityDelta: 1000e18
        });

        hook.afterAddLiquidity(address(this), key, params, delta, delta, hookData);
        
        // Should receive 1 POINT for 1 ETH
        assertEq(hook.balanceOf(USER), 1 ether);
    }

    function test_NoPointsForSellToken() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(ETH),
            currency1: Currency.wrap(TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Simulate selling TOKEN for ETH
        BalanceDelta delta = BalanceDelta.wrap(1 ether, -1000e18);
        bytes memory hookData = abi.encode(USER);

        SwapParams memory params = SwapParams({
            zeroForOne: false,
            amountSpecified: 1000e18,
            sqrtPriceLimitX96: 0
        });

        hook.afterSwap(address(this), key, params, delta, hookData);
        
        // Should receive 0 POINTS for selling TOKEN
        assertEq(hook.balanceOf(USER), 0);
    }
}
