// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Pyth SDK oficial (pull integration)
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

// Uniswap V3
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

// Uniswap V3 Factory para validar pools
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}


contract ParmeliaTreasury is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Integraciones / activos ---
    IERC20 public immutable PYUSD;
    IERC20 public immutable WETH;
    IPyth  public immutable pyth;
    ISwapRouter public immutable swapRouter;
    IUniswapV3Factory public immutable uniswapFactory;
    uint8  public immutable pyusdDecimals; // gas-save: cacheamos decimales
    uint8  public immutable wethDecimals;

    // --- Config estrategia (tuneable en runtime) ---
    bytes32 public ethUsdPriceFeedId;       // feed ETH/USD
    uint256 public maxEthPriceUsd1e18;      // compra si ETH/USD <= umbral (1e18)
    uint256 public swapChunkPYUSD;          // tamaño de cada swap (decimales PYUSD)
    uint256 public slippageBps;             // 100 = 1%
    uint256 public maxPriceAge;             // segundos
    uint256 public confMultiplier;          // 0..3: multiplica "conf" como amortiguador
    uint256 public execRewardBps;           // 0..100 (basis points) recompensa al ejecutor en PYUSD
    uint24  public poolFee;                 // Uniswap V3 fee tier
    uint256 public swapDeadline;            // deadline para swaps (segundos desde tx)
    uint256 public maxSlippageBps;          // máximo slippage permitido vs precio oráculo (100 = 1%)  

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
    error SlippageTooHigh();
    error PoolNotFound();

    // ---------- CONSTRUCTOR CORTO ----------
    constructor(
        address _pyusd,
        address _weth,
        address _pyth,
        address _swapRouter,
        address _uniswapFactory,
        bytes32 _ethUsdFeedId
    ) Ownable(msg.sender) {
        require(
            _pyusd != address(0) &&
            _weth  != address(0) &&
            _pyth  != address(0) &&
            _swapRouter != address(0) &&
            _uniswapFactory != address(0),
            "zero addr"
        );

        PYUSD = IERC20(_pyusd);
        WETH  = IERC20(_weth);
        pyth  = IPyth(_pyth);
        swapRouter = ISwapRouter(_swapRouter);
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
        wethDecimals = IERC20Metadata(_weth).decimals();
        pyusdDecimals = IERC20Metadata(_pyusd).decimals();

        // Set inicial
        ethUsdPriceFeedId  = _ethUsdFeedId;
        maxEthPriceUsd1e18 = 3_000 ether;                     // 3000 USD
        swapChunkPYUSD     = 10_000 * (10 ** pyusdDecimals);  // 10k PYUSD
        slippageBps        = 100;                             // 1%
        maxPriceAge        = 60;                              // 60 s
        confMultiplier     = 0;                               // 0 = no usar conf
        execRewardBps      = 0;                               // 0 = sin recompensa
        poolFee            = 3000;                            // 0.3% (fee tier más común)
        swapDeadline       = 600;                             // 10 minutos
        maxSlippageBps     = 200;                             // 2% máximo slippage permitido
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
        require(px.publishTime > 0, "invalid publishTime");

        uint256 price1e18 = _scaleTo1e18_signed(px.price, px.expo); // ETH/USD * 1e18

        // Opcional: endurecer usando "conf" (intervalo de confianza)
        if (confMultiplier > 0) {
            uint256 conf1e18 = _scaleTo1e18_unsigned(px.conf, px.expo);
            // Validar que conf no sea excesivamente alto (max 10% del precio)
            require(conf1e18 < price1e18 / 10, "conf too high");
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

        // Ajustar minOut a los decimales de WETH
        uint256 minOut;
        if (wethDecimals == 18) {
            minOut = minOut1e18;
        } else if (wethDecimals < 18) {
            minOut = minOut1e18 / (10 ** uint256(18 - wethDecimals));
        } else {
            minOut = minOut1e18 * (10 ** uint256(wethDecimals - 18));
        }

        // 6) Validar que existe el pool con el fee configurado
        address pool = uniswapFactory.getPool(address(PYUSD), address(WETH), poolFee);
        if (pool == address(0)) revert PoolNotFound();

        // 7) Approve + swap (V3 exactInputSingle)
        PYUSD.forceApprove(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(PYUSD),
            tokenOut: address(WETH),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + swapDeadline,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0 // sin límite de precio
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);

        // 8) Validación post-swap: verificar que el slippage real no exceda el máximo
        //    Slippage real = (expectedOut - amountOut) / expectedOut * 10000
        uint256 actualSlippageBps = ((expectedOut1e18 - (amountOut * (10 ** (18 - wethDecimals)))) * 10_000) / expectedOut1e18;
        if (actualSlippageBps > maxSlippageBps) revert SlippageTooHigh();

        // 9) Reward para el ejecutor (opcional)
        if (execRewardBps > 0) {
            uint256 reward = (amountIn * execRewardBps) / 10_000;
            if (reward > 0 && PYUSD.balanceOf(address(this)) >= reward) {
                PYUSD.safeTransfer(msg.sender, reward);
            }
        }
        
        emit StrategyExecuted(amountIn, amountOut, price1e18, block.timestamp);
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
        require(_confMultiplier <= 3, "conf multiplier too high");
        ethUsdPriceFeedId  = _feedId;
        maxEthPriceUsd1e18 = _maxEthPriceUsd1e18;
        swapChunkPYUSD     = _swapChunkPYUSD;
        slippageBps        = _slippageBps;
        maxPriceAge        = _maxPriceAge;
        confMultiplier     = _confMultiplier;
        execRewardBps      = _execRewardBps;
        emit StrategyParamsUpdated();
    }

    /// @notice Cambia el pool fee de Uniswap V3 (valida que el pool exista)
    /// @param _poolFee Fee tier: 500 (0.05%), 3000 (0.3%), 10000 (1%)
    function setPoolFee(uint24 _poolFee) external onlyOwner {
        require(
            _poolFee == 500 || _poolFee == 3000 || _poolFee == 10000,
            "invalid fee"
        );
        // Validar que existe el pool con este fee
        address pool = uniswapFactory.getPool(address(PYUSD), address(WETH), _poolFee);
        if (pool == address(0)) revert PoolNotFound();
        
        poolFee = _poolFee;
        emit StrategyParamsUpdated();
    }


    // Setters granulares (por si expones sliders individuales)
    function setMaxEthPriceUsd1e18(uint256 v) external onlyOwner { require(v > 0, "bad"); maxEthPriceUsd1e18 = v; emit StrategyParamsUpdated(); }
    function setSwapChunkPYUSD(uint256 v)     external onlyOwner { swapChunkPYUSD = v; emit StrategyParamsUpdated(); }
    function setSlippageBps(uint256 v)        external onlyOwner { require(v <= 10_000, "bad"); slippageBps = v; emit StrategyParamsUpdated(); }
    function setMaxPriceAge(uint256 v)        external onlyOwner { maxPriceAge = v; emit StrategyParamsUpdated(); }
    function setFeedId(bytes32 id)            external onlyOwner { ethUsdPriceFeedId = id; emit StrategyParamsUpdated(); }
    function setSwapDeadline(uint256 v)       external onlyOwner { require(v >= 60 && v <= 3600, "deadline range: 60-3600s"); swapDeadline = v; emit StrategyParamsUpdated(); }
    function setMaxSlippageBps(uint256 v)     external onlyOwner { require(v <= 1000, "max 10%"); maxSlippageBps = v; emit StrategyParamsUpdated(); }

    function setConfMultiplier(uint256 v) external onlyOwner {
        require(v <= 3, "too big");
        confMultiplier = v;
        emit StrategyParamsUpdated();
    }

    function setExecRewardBps(uint256 v) external onlyOwner {
        require(v <= 200, "reward too high");
        execRewardBps = v;
        emit StrategyParamsUpdated();
    }

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

    /// @notice Verifica si existe un pool para el par PYUSD/WETH con un fee específico
    /// @param fee Fee tier a verificar (500, 3000, 10000)
    /// @return exists True si el pool existe
    /// @return poolAddress Dirección del pool (address(0) si no existe)
    function checkPoolExists(uint24 fee) external view returns (bool exists, address poolAddress) {
        poolAddress = uniswapFactory.getPool(address(PYUSD), address(WETH), fee);
        exists = poolAddress != address(0);
    }

    receive() external payable {}
}
