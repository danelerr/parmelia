// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IPyth.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract ParmeliaTreasury is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Activos / Integraciones ---
    IERC20 public immutable PYUSD;
    IERC20 public immutable WETH;
    IPyth  public immutable pyth;
    IUniswapV2Router02 public immutable router;

    // --- Parámetros de estrategia (configurables) ---
    bytes32 public ethUsdPriceFeedId;      // feed ETH/USD
    uint256 public maxEthPriceUsd1e18;     // compra si ETH/USD <= umbral (1e18)
    uint256 public swapChunkPYUSD;         // amount por swap (decimales PYUSD)
    uint256 public slippageBps;            // 100 = 1%
    uint256 public maxPriceAge;            // seg

    // --- Eventos ---
    event Deposited(address indexed user, uint256 amount, uint256 ts);
    event Withdrawn(address indexed to, uint256 amount, uint256 ts);
    event StrategyExecuted(uint256 amountIn, uint256 amountOut, uint256 ethUsd1e18, uint256 ts);

    // --- Errores ---
    error InvalidParam();
    error InsufficientBalance();
    error PriceTooOld();
    error PriceAboveThreshold();
    error NothingToDo();

    // ---------- CONSTRUCTOR CORTO ----------
    constructor(
        address _pyusd,
        address _weth,
        address _pyth,
        address _router,
        bytes32 _ethUsdFeedId
    ) Ownable(msg.sender) {
        require(
            _pyusd != address(0) &&
            _weth  != address(0) &&
            _pyth  != address(0) &&
            _router!= address(0),
            "zero addr"
        );

        PYUSD = IERC20(_pyusd);
        WETH  = IERC20(_weth);
        pyth  = IPyth(_pyth);
        router= IUniswapV2Router02(_router);

        ethUsdPriceFeedId  = _ethUsdFeedId;

        // Defaults (puedes cambiarlos luego con setters)
        maxEthPriceUsd1e18 = 3_000 ether;  // 3000 USD
        swapChunkPYUSD     = 10_000 * 1e6; // si PYUSD usa 6 dec
        slippageBps        = 100;          // 1%
        maxPriceAge        = 60;           // 60 s
    }

    // --- Fondos ---

    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidParam();
        PYUSD.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount, block.timestamp);
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidParam();
        uint256 bal = PYUSD.balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance();
        PYUSD.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, block.timestamp);
    }

    // --- Estrategia ---

    function executeStrategy(bytes[] calldata updateData)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // 1) Paga fee exacto y actualiza Pyth
        uint256 fee = pyth.getUpdateFee(updateData);
        require(msg.value >= fee, "pyth fee too low");
        pyth.updatePriceFeeds{value: fee}(updateData);
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "refund failed");
        }

        // 2) Lee precio reciente y normaliza a 1e18
        (int64 p,, int32 expo, uint publishTime) =
            pyth.getPriceNoOlderThan(ethUsdPriceFeedId, maxPriceAge);
        if (publishTime + maxPriceAge < block.timestamp) revert PriceTooOld();
        require(p > 0, "bad price");
        uint256 price1e18 = _scaleTo1e18(p, expo); // ETH/USD * 1e18

        // 3) Regla
        if (price1e18 > maxEthPriceUsd1e18) revert PriceAboveThreshold();

        // 4) Amount in (chunk) y balance
        uint256 amountIn = swapChunkPYUSD;
        uint256 bal = PYUSD.balanceOf(address(this));
        if (bal == 0) revert NothingToDo();
        if (amountIn == 0 || amountIn > bal) amountIn = bal;

        // 5) Calcula minOut con precio oráculo y slippage
        uint8 decPY = IERC20Metadata(address(PYUSD)).decimals(); // típicamente 6
        uint256 amountIn1e18 = amountIn * (10 ** (18 - decPY));
        uint256 expectedOut1e18 = (amountIn1e18 * 1e18) / price1e18;
        uint256 minOut1e18 = (expectedOut1e18 * (10_000 - slippageBps)) / 10_000;
        uint256 amountOutMin = minOut1e18; // WETH 18

        // 6) Approve + swap (Uniswap V2)
        _approveIfNeeded(PYUSD, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(PYUSD);
        path[1] = address(WETH);

        uint256 deadline = block.timestamp + 300; // 5 min
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        emit StrategyExecuted(amounts[0], amounts[1], price1e18, block.timestamp);
    }

    // --- Admin (setters) ---

    function setStrategy(
        bytes32 _feedId,
        uint256 _maxEthPriceUsd1e18,
        uint256 _swapChunkPYUSD,
        uint256 _slippageBps,
        uint256 _maxPriceAge
    ) external onlyOwner {
        require(_slippageBps <= 10_000 && _maxEthPriceUsd1e18 > 0, "bad params");
        ethUsdPriceFeedId  = _feedId;
        maxEthPriceUsd1e18 = _maxEthPriceUsd1e18;
        swapChunkPYUSD     = _swapChunkPYUSD;
        slippageBps        = _slippageBps;
        maxPriceAge        = _maxPriceAge;
    }

    function setMaxEthPriceUsd1e18(uint256 v) external onlyOwner { require(v > 0, "bad"); maxEthPriceUsd1e18 = v; }
    function setSwapChunkPYUSD(uint256 v)     external onlyOwner { swapChunkPYUSD = v; }
    function setSlippageBps(uint256 v)        external onlyOwner { require(v <= 10_000, "bad"); slippageBps = v; }
    function setMaxPriceAge(uint256 v)        external onlyOwner { maxPriceAge = v; }
    function setFeedId(bytes32 id)            external onlyOwner { ethUsdPriceFeedId = id; }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // --- Helpers ---

    function _approveIfNeeded(IERC20 token, address spender, uint256 amount) internal {
        uint256 allowance = token.allowance(address(this), spender);
        if (allowance < amount) {
            token.forceApprove(spender, type(uint256).max);
        }
    }

    function _scaleTo1e18(int64 price, int32 expo) internal pure returns (uint256) {
        require(price > 0, "neg price");
        int32 e = expo + 18;
        uint256 p = uint256(uint64(price));
        if (e >= 0) return p * (10 ** uint32(uint32(e)));
        return p / (10 ** uint32(uint32(-e)));
    }

    // --- Vistas para el frontend ---
    function balances() external view returns (uint256 pyusd, uint256 weth) {
        pyusd = PYUSD.balanceOf(address(this));
        weth  = WETH.balanceOf(address(this));
    }

    receive() external payable {}
}
