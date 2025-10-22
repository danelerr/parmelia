// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Router02.sol";

// Pyth SDK oficial (pull integration)
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";


contract ParmeliaTreasury is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Integraciones / activos ---
    IERC20 public immutable PYUSD;
    IERC20 public immutable WETH;
    IPyth  public immutable pyth;
    IUniswapV2Router02 public immutable router;
    uint8  public immutable pyusdDecimals; // gas-save: cacheamos decimales

    // --- Config estrategia (tuneable en runtime) ---
    bytes32 public ethUsdPriceFeedId;       // feed ETH/USD
    uint256 public maxEthPriceUsd1e18;      // compra si ETH/USD <= umbral (1e18)
    uint256 public swapChunkPYUSD;          // tamaño de cada swap (decimales PYUSD)
    uint256 public slippageBps;             // 100 = 1%
    uint256 public maxPriceAge;             // segundos
    uint256 public confMultiplier;          // 0..3: multiplica "conf" como amortiguador
    uint256 public execRewardBps;           // 0..100 (basis points) recompensa al ejecutor en PYUSD

    // --- Eventos ---
    event Deposited(address indexed user, uint256 amount, uint256 ts);
    event Withdrawn(address indexed to, uint256 amount, uint256 ts);
    event StrategyExecuted(uint256 amountIn, uint256 amountOut, uint256 ethUsd1e18, uint256 ts);
    event StrategyParamsUpdated();

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

        // Auto-detect decimales de PYUSD y cachea (gas-save)
        pyusdDecimals = IERC20Metadata(_pyusd).decimals();

        // Set inicial
        ethUsdPriceFeedId  = _ethUsdFeedId;
        maxEthPriceUsd1e18 = 3_000 ether;                     // 3000 USD
        swapChunkPYUSD     = 10_000 * (10 ** pyusdDecimals);  // 10k PYUSD
        slippageBps        = 100;                             // 1%
        maxPriceAge        = 60;                              // 60 s
        confMultiplier     = 0;                               // 0 = no usar conf
        execRewardBps      = 0;                               // 0 = sin recompensa
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

    // --- Estrategia (Pyth pull + swap) ---

    /// @notice Ejecuta la regla usando Pyth (pull): update → read → swap
    /// @param priceUpdate blobs de Hermes (bytes[]) con los updates de precio
    function executeStrategy(bytes[] calldata priceUpdate)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // 1) Calcular y pagar el fee exacto a Pyth + actualizar feed (requerido por el bounty)
        uint256 fee = pyth.getUpdateFee(priceUpdate);
        require(msg.value == fee, "bad fee");
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);

        // 2) Leer precio "fresco" con límite de antigüedad
        PythStructs.Price memory px = pyth.getPriceNoOlderThan(ethUsdPriceFeedId, maxPriceAge);
        require(px.price > 0, "bad price");

        uint256 price1e18 = _scaleTo1e18_signed(px.price, px.expo); // ETH/USD * 1e18

        // Opcional: endurecer usando "conf" (intervalo de confianza)
        if (confMultiplier > 0) {
            uint256 conf1e18 = _scaleTo1e18_unsigned(px.conf, px.expo);
            // Precio ajustado al alza → más conservador al estimar WETH out
            price1e18 += confMultiplier * conf1e18;
        }

        // 3) Regla: comprar si ETH/USD <= umbral
        if (price1e18 > maxEthPriceUsd1e18) revert PriceAboveThreshold();

        // 4) Monto a swappear (chunk) y balance
        uint256 amountIn = swapChunkPYUSD;
        uint256 bal = PYUSD.balanceOf(address(this));
        if (bal == 0) revert NothingToDo();
        if (amountIn == 0 || amountIn > bal) amountIn = bal;

        // 5) amountOutMin con precio del oráculo + slippage
        //    PYUSD ~ 1 USD, escalamos a 1e18
        uint256 amountIn1e18 = amountIn * (10 ** (18 - pyusdDecimals));
        uint256 expectedOut1e18 = (amountIn1e18 * 1e18) / price1e18;
        uint256 minOut1e18 = (expectedOut1e18 * (10_000 - slippageBps)) / 10_000;

        // 6) Approve + swap (V2)
        PYUSD.forceApprove(address(router), amountIn);

        
        address[] memory path = new address[](2);
        path[0] = address(PYUSD);
        path[1] = address(WETH);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            minOut1e18,               // WETH usualmente 18 dec
            path,
            address(this),
            block.timestamp + 300      // 5 min de ventana
        );


        // 7) Reward para el ejecutor (opcional)
        if (execRewardBps > 0) {
            uint256 reward = (amountIn * execRewardBps) / 10_000;
            if (reward > 0 && PYUSD.balanceOf(address(this)) >= reward) {
                PYUSD.safeTransfer(msg.sender, reward);
            }
        }

        emit StrategyExecuted(amounts[0], amounts[1], price1e18, block.timestamp);
    }

    // --- Admin (setters) ---

    function setStrategy(
        bytes32 _feedId,
        uint256 _maxEthPriceUsd1e18,
        uint256 _swapChunkPYUSD,
        uint256 _slippageBps,
        uint256 _maxPriceAge,
        uint256 _confMultiplier,
        uint256 _execRewardBps
    ) external onlyOwner {
        require(_slippageBps <= 10_000 && _maxEthPriceUsd1e18 > 0, "bad params");
        require(_execRewardBps <= 200, "reward too high"); // máx 2% por seguridad
        ethUsdPriceFeedId  = _feedId;
        maxEthPriceUsd1e18 = _maxEthPriceUsd1e18;
        swapChunkPYUSD     = _swapChunkPYUSD;
        slippageBps        = _slippageBps;
        maxPriceAge        = _maxPriceAge;
        confMultiplier     = _confMultiplier;
        execRewardBps      = _execRewardBps;
        emit StrategyParamsUpdated();
    }

    // Setters granulares (por si expones sliders individuales)
    function setMaxEthPriceUsd1e18(uint256 v) external onlyOwner { require(v > 0, "bad"); maxEthPriceUsd1e18 = v; emit StrategyParamsUpdated(); }
    function setSwapChunkPYUSD(uint256 v)     external onlyOwner { swapChunkPYUSD = v; emit StrategyParamsUpdated(); }
    function setSlippageBps(uint256 v)        external onlyOwner { require(v <= 10_000, "bad"); slippageBps = v; emit StrategyParamsUpdated(); }
    function setMaxPriceAge(uint256 v)        external onlyOwner { maxPriceAge = v; emit StrategyParamsUpdated(); }
    function setFeedId(bytes32 id)            external onlyOwner { ethUsdPriceFeedId = id; emit StrategyParamsUpdated(); }
    function setConfMultiplier(uint256 v)     external onlyOwner { confMultiplier = v; emit StrategyParamsUpdated(); }
    function setExecRewardBps(uint256 v)      external onlyOwner { require(v <= 200, "reward too high"); execRewardBps = v; emit StrategyParamsUpdated(); }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // Recuperar tokens enviados por error (excepto los principales)
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(PYUSD) && token != address(WETH), "main assets");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // --- Helpers de escala para Pyth ---
    function _scaleTo1e18_signed(int64 price, int32 expo) internal pure returns (uint256) {
        require(price > 0, "neg price");
        int256 p = int256(price);
        int32 e = expo + 18;
        if (e >= 0) return uint256(p) * (10 ** uint32(uint32(e)));
        return uint256(p) / (10 ** uint32(uint32(-e)));
    }

    function _scaleTo1e18_unsigned(uint64 value, int32 expo) internal pure returns (uint256) {
        uint256 p = uint256(value);
        int32 e = expo + 18;
        if (e >= 0) return p * (10 ** uint32(uint32(e)));
        return p / (10 ** uint32(uint32(-e)));
    }

    // --- Vistas útiles para el frontend ---
    function balances() external view returns (uint256 pyusd, uint256 weth) {
        pyusd = PYUSD.balanceOf(address(this));
        weth  = WETH.balanceOf(address(this));
    }

    receive() external payable {}
}
