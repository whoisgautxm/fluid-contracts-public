// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title library that calculates number "tick" and "ratioX96" from this: ratioX96 = (1.0015^tick) * 2^96
/// @notice this library is used in Fluid Vault protocol for optimiziation.
/// @dev "tick" supports between -32768 and 32768. "ratioX96" supports between 37019542 and 169561839080424764793230651497174835072620786440549
library TickMath {
    /// The minimum tick that can be passed in getRatioAtTick. 1.0015**-32768
    int24 internal constant MIN_TICK = -32768;
    /// The maximum tick that can be passed in getRatioAtTick. computed from 1.0015**32768
    int24 internal constant MAX_TICK = 32768;

    uint256 internal constant FACTOR00 = 0x100000000000000000000000000000000;
    uint256 internal constant FACTOR01 = 0xff9dd7de423466c20352b1246ce4856f;
    uint256 internal constant FACTOR02 = 0xff3bd55f4488ad277531fa1c725a66d0; // 1.0015 ** 2
    uint256 internal constant FACTOR03 = 0xfe78410fd6498b73cb96a6917f853259; // 1.0015 ** 4
    uint256 internal constant FACTOR04 = 0xfcf2d9987c9be178ad5bfeffaa123273; // 1.0015 ** 8
    uint256 internal constant FACTOR05 = 0xf9ef02c4529258b057769680fc6601b3; // 1.0015 ** 16
    uint256 internal constant FACTOR06 = 0xf402d288133a85a17784a411f7aba082; // 1.0015 ** 32
    uint256 internal constant FACTOR07 = 0xe895615b5beb6386553757b0352bda90; // 1.0015 ** 64
    uint256 internal constant FACTOR08 = 0xd34f17a00ffa00a8309940a15930391a; // 1.0015 ** 128
    uint256 internal constant FACTOR09 = 0xae6b7961714e20548d88ea5123f9a0ff; // 1.0015 ** 256
    uint256 internal constant FACTOR10 = 0x76d6461f27082d74e0feed3b388c0ca1; // 1.0015 ** 512
    uint256 internal constant FACTOR11 = 0x372a3bfe0745d8b6b19d985d9a8b85bb; // 1.0015 ** 1024
    uint256 internal constant FACTOR12 = 0x0be32cbee48979763cf7247dd7bb539d; // 1.0015 ** 2048
    uint256 internal constant FACTOR13 = 0x8d4f70c9ff4924dac37612d1e2921e; // 1.0015 ** 4096
    uint256 internal constant FACTOR14 = 0x4e009ae5519380809a02ca7aec77; // 1.0015 ** 8192
    uint256 internal constant FACTOR15 = 0x17c45e641b6e95dee056ff10; // 1.0015 ** 16384
    uint256 internal constant FACTOR16 = 0x0234df96a9058b8e; // 1.0015 ** 32768

    /// The minimum value that can be returned from getRatioAtTick. Equivalent to getRatioAtTick(MIN_TICK). Equivalent to `(1 << 96) * (1.0015**-32768)`
    uint256 internal constant MIN_RATIOX96 = 37019543;
    /// The maximum value that can be returned from getRatioAtTick. Equivalent to getRatioAtTick(MAX_TICK). Equivalent to `(1 << 96) * (1.0015**32768)`
    uint256 internal constant MAX_RATIOX96 = 169561839080424764793230651497174835072620786440549;

    uint256 internal constant ZERO_TICK_SCALED_RATIO = 0x1000000000000000000000000; // 1 << 96 // 79228162514264337593543950336
    uint256 internal constant _1E18 = 1000000000000000000;

    /// @notice ratioX96 = (1.0015^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return ratioX96 ratio = (debt amount/collateral amount)
    function getRatioAtTick(int tick) internal pure returns (uint256 ratioX96) {
        assembly {
            let absTick_ := sub(xor(tick, sar(255, tick)), sar(255, tick))

            if gt(absTick_, MAX_TICK) {
                revert(0, 0)
            }
            let factor_ := FACTOR00
            // let cond :=
            if and(absTick_, 0x1) {
                factor_ := FACTOR01
            }
            if and(absTick_, 0x2) {
                factor_ := shr(128, mul(factor_, FACTOR02))
            }
            if and(absTick_, 0x4) {
                factor_ := shr(128, mul(factor_, FACTOR03))
            }
            if and(absTick_, 0x8) {
                factor_ := shr(128, mul(factor_, FACTOR04))
            }
            if and(absTick_, 0x10) {
                factor_ := shr(128, mul(factor_, FACTOR05))
            }
            if and(absTick_, 0x20) {
                factor_ := shr(128, mul(factor_, FACTOR06))
            }
            if and(absTick_, 0x40) {
                factor_ := shr(128, mul(factor_, FACTOR07))
            }
            if and(absTick_, 0x80) {
                factor_ := shr(128, mul(factor_, FACTOR08))
            }
            if and(absTick_, 0x100) {
                factor_ := shr(128, mul(factor_, FACTOR09))
            }
            if and(absTick_, 0x200) {
                factor_ := shr(128, mul(factor_, FACTOR10))
            }
            if and(absTick_, 0x400) {
                factor_ := shr(128, mul(factor_, FACTOR11))
            }
            if and(absTick_, 0x800) {
                factor_ := shr(128, mul(factor_, FACTOR12))
            }
            if and(absTick_, 0x1000) {
                factor_ := shr(128, mul(factor_, FACTOR13))
            }
            if and(absTick_, 0x2000) {
                factor_ := shr(128, mul(factor_, FACTOR14))
            }
            if and(absTick_, 0x4000) {
                factor_ := shr(128, mul(factor_, FACTOR15))
            }
            if and(absTick_, 0x8000) {
                factor_ := shr(128, mul(factor_, FACTOR16))
            }

            let precision_ := 0
            if iszero(and(tick, 0x8000000000000000000000000000000000000000000000000000000000000000)) {
                factor_ := div(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, factor_)
                // we round up in the division so getTickAtRatio of the output price is always consistent
                if mod(factor_, 0x100000000) {
                    precision_ := 1
                }
            }
            ratioX96 := add(shr(32, factor_), precision_)
        }
    }

    /// @notice ratioX96 = (1.0015^tick) * 2^96
    /// @dev Throws if ratioX96 > max ratio || ratioX96 < min ratio
    /// @param ratioX96 The input ratio; ratio = (debt amount/collateral amount)
    /// @return tick The output tick for the above formula. Returns in round down form. if tick is 123.23 then 123, if tick is -123.23 then returns -124
    /// @return perfectRatioX96 perfect ratio for the above tick
    function getTickAtRatio(uint256 ratioX96) internal pure returns (int tick, uint perfectRatioX96) {
        assembly {
            if or(gt(ratioX96, MAX_RATIOX96), lt(ratioX96, MIN_RATIOX96)) {
                revert(0, 0)
            }

            let cond := lt(ratioX96, ZERO_TICK_SCALED_RATIO)
            let factor_

            if iszero(cond) {
                factor_ := div(mul(ratioX96, _1E18), ZERO_TICK_SCALED_RATIO)
            }
            if cond {
                factor_ := div(mul(ZERO_TICK_SCALED_RATIO, _1E18), ratioX96)
            }

            // put in https://www.wolframalpha.com/ whole equation: (1.0015^tick) * 2^96 * 10^18 / 79228162514264337593543950336

            // for tick = 32768
            // ratioX96 = (1.0015^32768) * 2^96 = 169561839080424764589165145670046701398124475902882 (MAX_RATIOX96)
            // 169561839080424764589165145670046701398124475902882 * 10^18 / 79228162514264337593543950336 =
            // 2140171293886774652197095042041204890073.31589380293029738610
            if iszero(lt(factor_, 2140171293886774652197095042041204890073)) {
                // for max
                tick := or(tick, 0x8000)
                factor_ := div(mul(factor_, _1E18), 2140171293886774652197095042041204890073)
            }
            // for tick = 16384
            // ratioX96 = (1.0015^16384) * 2^96 = 3665252098134783297721995888537077351735
            // 3665252098134783297721995888537077351735 * 10^18 / 79228162514264337593543950336 =
            // 46261985407965087163484043083.4525598506131964639489434655721
            if iszero(lt(factor_, 46261985407965087163484043083)) {
                tick := or(tick, 0x4000)
                factor_ := div(mul(factor_, _1E18), 46261985407965087163484043083)
            }
            // for tick = 8192
            // ratioX96 = (1.0015^8192) * 2^96 = 17040868196391020479062776466509865
            // 17040868196391020479062776466509865 * 10^18 / 79228162514264337593543950336 =
            // 215085995378511539117674.904491623037648642153898377655505172
            if iszero(lt(factor_, 215085995378511539117675)) {
                tick := or(tick, 0x2000)
                factor_ := div(mul(factor_, _1E18), 215085995378511539117675)
            }
            // for tick = 4096
            // ratioX96 = (1.0015^4096) * 2^96 = 36743933851015821532611831851150
            // 36743933851015821532611831851150 * 10^18 / 79228162514264337593543950336 =
            // 463773646705493108830.028666489777607649742626173648716941385
            if iszero(lt(factor_, 463773646705493108830)) {
                tick := or(tick, 0x1000)
                factor_ := div(mul(factor_, _1E18), 463773646705493108830)
            }
            // for tick = 2048
            // ratioX96 = (1.0015^2048) * 2^96 = 1706210527034005899209104452335
            // 1706210527034005899209104452335 * 10^18 / 79228162514264337593543950336 =
            // 21535404493658648454.6834476006357108484096046743300420319322
            if iszero(lt(factor_, 21535404493658648455)) {
                tick := or(tick, 0x800)
                factor_ := div(mul(factor_, _1E18), 21535404493658648455)
            }
            // for tick = 1024
            // ratioX96 = (1.0015^1024) * 2^96 = 367668226692760093024536487236
            // 367668226692760093024536487236 * 10^18 / 79228162514264337593543950336 =
            // 4640625442077678440.08185024950588990554136265212906454481127
            if iszero(lt(factor_, 4640625442077678440)) {
                tick := or(tick, 0x400)
                factor_ := div(mul(factor_, _1E18), 4640625442077678440)
            }
            // for tick = 512
            // ratioX96 = (1.0015^512) * 2^96 = 170674186729409605620119663668
            // 170674186729409605620119663668 * 10^18 / 79228162514264337593543950336 =
            // 2154211095059552988.02281577031879604792139232258508172947569
            if iszero(lt(factor_, 2154211095059552988)) {
                tick := or(tick, 0x200)
                factor_ := div(mul(factor_, _1E18), 2154211095059552988)
            }
            // for tick = 256
            // ratioX96 = (1.0015^256) * 2^96 = 116285004205991934861656513301
            // 116285004205991934861656513301 * 10^18 / 79228162514264337593543950336 =
            // 1467723098905087406.07270614667650899656438875541505058062410
            if iszero(lt(factor_, 1467723098905087406)) {
                tick := or(tick, 0x100)
                factor_ := div(mul(factor_, _1E18), 1467723098905087406)
            }
            // for tick = 128
            // ratioX96 = (1.0015^128) * 2^96 = 95984619659632141743747099590
            // 95984619659632141743747099590 * 10^18 / 79228162514264337593543950336 =
            // 1211496223231870998.17270416157248837742741760456796835775887
            if iszero(lt(factor_, 1211496223231870998)) {
                tick := or(tick, 0x80)
                factor_ := div(mul(factor_, _1E18), 1211496223231870998)
            }
            // for tick = 64
            // ratioX96 = (1.0015^64) * 2^96 = 87204845308406958006717891124
            // 87204845308406958006717891124 * 10^18 / 79228162514264337593543950336 =
            // 1100679891354371476.85980801568068573422377364214113968609839
            if iszero(lt(factor_, 1100679891354371477)) {
                tick := or(tick, 0x40)
                factor_ := div(mul(factor_, _1E18), 1100679891354371477)
            }
            // for tick = 32
            // ratioX96 = (1.0015^32) * 2^96 = 83120873769022354029916374475
            // 83120873769022354029916374475 * 10^18 / 79228162514264337593543950336 =
            // 1049132923587078872.70979599831816586773651266562785765558183
            if iszero(lt(factor_, 1049132923587078873)) {
                tick := or(tick, 0x20)
                factor_ := div(mul(factor_, _1E18), 1049132923587078873)
            }
            // for tick = 16
            // ratioX96 = (1.0015^16) * 2^96 = 81151180492336368327184716176
            // 81151180492336368327184716176 * 10^18 / 79228162514264337593543950336 =
            // 1024271899247010911.91840927762844039579442328381455567932128
            if iszero(lt(factor_, 1024271899247010912)) {
                tick := or(tick, 0x10)
                factor_ := div(mul(factor_, _1E18), 1024271899247010912)
            }
            // for tick = 8
            // ratioX96 = (1.0015^8) * 2^96 = 80183906840906820640659903620
            // 80183906840906820640659903620 * 10^18 / 79228162514264337593543950336 =
            // 1012063189354800569.07421312890625
            if iszero(lt(factor_, 1012063189354800569)) {
                tick := or(tick, 0x8)
                factor_ := div(mul(factor_, _1E18), 1012063189354800569)
            }
            // for tick = 4
            // ratioX96 = (1.0015^4) * 2^96 = 79704602139525152702959747603
            // 79704602139525152702959747603 * 10^18 / 79228162514264337593543950336 =
            // 1006013513505062500
            if iszero(lt(factor_, 1006013513505062500)) {
                tick := or(tick, 0x4)
                factor_ := div(mul(factor_, _1E18), 1006013513505062500)
            }
            // for tick = 2
            // ratioX96 = (1.0015^2) * 2^96 = 79466025265172787701084167660
            // 79466025265172787701084167660 * 10^18 / 79228162514264337593543950336 =
            // 1003002250000000000
            if iszero(lt(factor_, 1003002250000000000)) {
                tick := or(tick, 0x2)
                factor_ := div(mul(factor_, _1E18), 1003002250000000000)
            }
            // for tick = 1
            // ratioX96 = (1.0015^1) * 2^96 = 79347004758035734099934266261
            // 79347004758035734099934266261 * 10^18 / 79228162514264337593543950336 =
            // 1001500000000000000
            if iszero(lt(factor_, 1001500000000000000)) {
                tick := or(tick, 0x1)
                factor_ := div(mul(factor_, _1E18), 1001500000000000000)
            }
            if iszero(cond) {
                perfectRatioX96 := div(mul(ratioX96, _1E18), factor_)
            }
            if cond {
                tick := not(tick)
                perfectRatioX96 := div(mul(ratioX96, factor_), 1001500000000000000)
            }
        }
    }
}
