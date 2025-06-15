// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapLimiterHook} from "../src/SwapLimiterHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Fixtures} from "./utils/libraries/Fixtures.sol";

contract SwapLimiterHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SwapLimiterHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    event SwapLimitReached(address indexed user, uint256 timestamp);

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("SwapLimiterHook.sol:SwapLimiterHook", constructorArgs, flags);
        hook = SwapLimiterHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            10_000e18,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testDirectBeforeSwap() public {
        address sender = address(this);
        IPoolManager.SwapParams memory params;
        bytes memory hookData;

        for (uint i = 0; i < 5; i++) {
            (bytes4 selector,,) = hook.beforeSwap(sender, key, params, hookData);
            assertEq(selector, SwapLimiterHook.beforeSwap.selector);
            console.log("Swap %d, Remaining swaps: %d", i + 1, hook.getRemainingSwaps(sender));
        }

        vm.expectRevert("Swap limit reached for this hour");
        hook.beforeSwap(sender, key, params, hookData);
    }

    function testSwapLimiter() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap

        console.log("Initial remaining swaps: %d", hook.getRemainingSwaps(address(this)));

        // Perform 5 swaps (should succeed)
        for (uint i = 0; i < 5; i++) {
            // Manually call beforeSwap to simulate the hook being triggered
            (bytes4 selector,,) = hook.beforeSwap(address(this), key, IPoolManager.SwapParams({zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0}), ZERO_BYTES);
            assertEq(selector, SwapLimiterHook.beforeSwap.selector);

            BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
            assertEq(int256(swapDelta.amount0()), amountSpecified);
            console.log("Swap %d succeeded. Remaining swaps: %d", i + 1, hook.getRemainingSwaps(address(this)));
        }

        // The 6th swap should revert
        vm.expectRevert("Swap limit reached for this hour");
        hook.beforeSwap(address(this), key, IPoolManager.SwapParams({zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0}), ZERO_BYTES);

        // Attempt the 6th swap (should fail)
        vm.expectRevert(abi.encodeWithSignature("Wrap__FailedHookCall(address,bytes)", address(hook), abi.encodeWithSignature("Error(string)", "Swap limit reached for this hour")));
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check remaining swaps
        uint256 remainingSwaps = hook.getRemainingSwaps(address(this));
        console.log("Final remaining swaps: %d", remainingSwaps);
        assertEq(remainingSwaps, 0, "Should have 0 remaining swaps");
    }

    function testSwapLimitReachedEvent() public {
        address sender = address(this);
        IPoolManager.SwapParams memory params;
        bytes memory hookData;

        for (uint i = 0; i < 4; i++) {
            hook.beforeSwap(sender, key, params, hookData);
        }

        vm.expectEmit(true, false, false, true);
        emit SwapLimitReached(sender, block.timestamp);
        hook.beforeSwap(sender, key, params, hookData);
    }
}
