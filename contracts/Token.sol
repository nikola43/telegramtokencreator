// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Token is ERC20Burnable, Ownable {
    // ADDRESSESS -------------------------------------------------------------------------------------------
    address public immutable router;
    address public immutable lpPair; // Liquidity token address
    address public treasury; // owner fee wallet address

    // VALUES -----------------------------------------------------------------------------------------------
    uint256 public swapThreshold; // swap tokens limit

    // BOOLEANS ---------------------------------------------------------------------------------------------
    bool private inSwap; // used for dont take fee on swaps

    // MAPPINGS ---------------------------------------------------------------------------------------------
    mapping(address => bool) public pairs;
    mapping(address => bool) public isExcludedFromFee; // list of users excluded from fee

    // STRUCTS ----------------------------------------------------------------------------------------------
    struct Fees {
        uint16 buyFee; // fee when people BUY tokens
        uint16 sellFee; // fee when people SELL tokens
        uint16 transferFee; // fee when people TRANSFER tokens
    }

    // OBJECTS ----------------------------------------------------------------------------------------------
    Fees public _feesRates; // fees rates

    // MODIFIERS --------------------------------------------------------------------------------------------
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // CONSTRUCTOR ------------------------------------------------------------------------------------------
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 supply,
        address[] memory addresses, // routerAddress, treasuryAddress
        uint16[] memory percents //buyFee, sellFee
    ) ERC20(tokenName, tokenSymbol) {
        require(addresses.length == 2, "Invalid address argument");
        require(addresses[0] != address(0), "Invalid router address");
        require(addresses[1] != address(0), "Invalid treasury address");
        require(percents.length == 2, "Invalid percent argument");
        require(percents[0] <= 4500 && percents[1] <= 4500, "Too hight tax");

        router = addresses[0];
        treasury = addresses[1];

        _feesRates = Fees({
            buyFee: percents[0],
            sellFee: percents[1],
            transferFee: 0
        });

        // Create a uniswap pair
        (, bytes memory data) = factory().call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("createPair(address,address)"))),
                address(this),
                WETH()
            )
        );
        lpPair = abi.decode(data, (address));
        pairs[lpPair] = true;

        // exclude from fees
        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[treasury] = true;
        isExcludedFromFee[address(this)] = true;

        // contract performs swap when have 1k tokens balance
        swapThreshold = 1000 ether;

        _mint(msg.sender, supply);
    }

    // To receive ETH from dexRouter when swapping
    receive() external payable {}

    // Set fees
    function setTaxes(
        uint16 buyFee,
        uint16 sellFee,
        uint16 transferFee
    ) external onlyOwner {
        require(buyFee <= 4500 && sellFee <= 4500, "Too hight tax");
        _feesRates.buyFee = buyFee;
        _feesRates.sellFee = sellFee;
        _feesRates.transferFee = transferFee;
    }

    function setSwapThreshold(uint256 value) external onlyOwner {
        swapThreshold = value;
    }

    function setTreasuryAddress(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (inSwap) {
            super._transfer(from, to, amount);
            return;
        }

        // if contract balance is greater than swapThreshold
        uint256 swapAmount = balanceOf(address(this));
        if (
            swapAmount >= swapThreshold &&
            !inSwap &&
            from != lpPair &&
            balanceOf(lpPair) > swapAmount &&
            !isExcludedFromFee[to] &&
            !isExcludedFromFee[from]
        ) {
            swapTokensForNative(swapAmount, treasury);
        }

        _finalizeTransfer(from, to, amount);
    }

    function WETH() internal view returns (address) {
        (, bytes memory data) = router.staticcall(
            abi.encodeWithSelector(bytes4(keccak256(bytes("WETH()"))))
        );
        return abi.decode(data, (address));
    }

    function factory() internal view returns (address) {
        (, bytes memory data) = router.staticcall(
            abi.encodeWithSelector(bytes4(keccak256(bytes("factory()"))))
        );
        return abi.decode(data, (address));
    }

    function swapTokensForNative(uint256 amount, address to) private swapping {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH();

        _approve(address(this), router, amount);

        (bool success, ) = router.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        bytes(
                            "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)"
                        )
                    )
                ),
                amount,
                0,
                path,
                to,
                block.timestamp + 300
            )
        );
        require(success, "Error: swapTokensForNative");
    }

    function _finalizeTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        bool takeFee = !inSwap;
        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 feeAmount = calcBuySellTransferFee(from, to, amount);

            if (feeAmount > 0) {
                amount -= feeAmount;
                super._transfer(from, address(this), feeAmount);
            }
        }

        super._transfer(from, to, amount);
    }

    function calcBuySellTransferFee(
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 feePercent;

        // BUY -> FROM == LP ADDRESS
        if (pairs[from]) {
            feePercent = _feesRates.buyFee;
        }
        // SELL -> TO == LP ADDRESS
        else if (pairs[to]) {
            feePercent = _feesRates.sellFee;
        }
        // TRANSFER
        else {
            feePercent = _feesRates.transferFee;
        }

        // CALC FEES AMOUT
        if (feePercent > 0) {
            return (amount * feePercent) / 10000;
        }

        return 0;
    }

    function excludeFromFee(address account, bool val) external onlyOwner {
        isExcludedFromFee[account] = val;
    }
}
