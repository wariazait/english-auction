// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EnglishAuction is Ownable {
    struct Auction {
        IERC20 token;
        uint256 tokenCount;
        uint256 start;
        uint256 duration;
    }

    struct Bid {
        address account;
        uint256 value;
    }

    Auction private _auction;
    Bid private _highestBid;
    address private _wallet;

    event WalletSet(address wallet);
    event AuctionStarted(Auction auction);
    event AuctionCanceled(Auction auction);
    event AuctionFinished(Auction auction, Bid bid);
    event BidMaked(address account, uint256 value);

    error WalletAddressZero();
    error TooEarlyStartTime();
    error AuctionAlreadyStarted();
    error AuctionAlreadyFinished();
    error AuctionNotFinished();
    error AuctionNotStarted();
    error NotEnoughMoney();
    error NotEnoughTokens();
    error TokenAllowanceNeeded();
    error NegativeStartPrice();
    error TransferMoneyFailed();

    /// @notice Разрешает вызов функции, когда аукцион стартовал.
    modifier whenStarted() {
        _whenStarted();
        _;
    }

    function _whenStarted() internal view {
        require(
            block.timestamp >= _auction.start && _auction.start != 0,
            AuctionNotStarted()
        );
    }

    constructor(address wallet) Ownable(msg.sender) {
        require(wallet != address(0), WalletAddressZero());
        _wallet = wallet;
        emit WalletSet(wallet);
    }

    /**
     * @notice Стартует аукцион.
     * @param _token Продаваемый токен.
     * @param countTokens Количество продаваемых токенов.
     * @param startTime Время начала аукциона.
     * @param _duration Длительность аукциона.
     * @dev Аукцион можно начать заранее, указав соответствующее время начала.
     */
    function start(
        IERC20 _token,
        uint256 countTokens,
        uint256 startTime,
        uint256 _duration,
        uint256 startPrice
    ) external onlyOwner {
        require(_auction.start == 0, AuctionAlreadyStarted());
        require(startTime >= block.timestamp, TooEarlyStartTime());
        require(_token.balanceOf(owner()) >= countTokens, NotEnoughTokens());
        require(
            _token.allowance(owner(), address(this)) >= countTokens,
            TokenAllowanceNeeded()
        );

        _token.transferFrom(owner(), address(this), countTokens);

        _auction = Auction({
            token: _token,
            tokenCount: countTokens,
            start: startTime,
            duration: _duration
        });

        _highestBid = Bid({account: address(0), value: startPrice});

        emit AuctionStarted(_auction);
    }

    /// @notice Позволяет сделать ставку.
    function bid() external payable whenStarted {
        require(
            block.timestamp < _auction.start + _auction.duration,
            AuctionAlreadyFinished()
        );
        require(msg.value > _highestBid.value, NotEnoughMoney());

        Bid memory currentBid = _highestBid;
        _highestBid = Bid({account: msg.sender, value: msg.value});
        _returnMoney(currentBid);

        emit BidMaked(msg.sender, msg.value);
    }

    /**
     * @notice Отменяет аукцион.
     * @dev Отменить аукцион может только его владелец и только после старта.
     */
    function cancel() external whenStarted onlyOwner {
        Auction memory auction = _auction;
        Bid memory currentBid = _highestBid;

        _clearAuction();
        _returnMoney(currentBid);

        auction.token.transfer(owner(), auction.tokenCount);

        emit AuctionCanceled(auction);
    }

    /**
     * @notice Завершает аукцион.
     * @dev Закончить аукцион может любой адрес после окончания работы аукциона.
     */
    function finish() external {
        require(
            block.timestamp > _auction.start + _auction.duration,
            AuctionNotFinished()
        );

        Auction memory auction = _auction;
        Bid memory highestBid = _highestBid;

        _clearAuction();

        if (highestBid.account != address(0)) {
            _transferMoney(_wallet, highestBid.value);
            auction.token.transfer(highestBid.account, auction.tokenCount);
        } else {
            auction.token.transfer(owner(), auction.tokenCount);
        }

        emit AuctionFinished(auction, highestBid);
    }

    /// @notice Возвращает информацию о текущей наибольшей ставке.
    function getHighestBid() external view returns (Bid memory) {
        return _highestBid;
    }

    /// @notice Возвращает информацию по аукциону.
    function getAuction() external view returns (Auction memory) {
        return _auction;
    }

    /// @notice Возвращает адрес кошелька для вывода собранных с продажи средств.
    function getWallet() external view returns (address) {
        return _wallet;
    }

    /**
     * @notice Позволяет изменить кошелек для вывода собранных с продажи средств.
     * @param wallet Новый адрес кошелька.
     * @dev Доступно только владельцу аукциона.
     */
    function setWallet(address wallet) external onlyOwner {
        _wallet = wallet;

        emit WalletSet(wallet);
    }

    /// @dev Позволяет вернуть деньги с предыдущей ставки, при условии что она была сделана.
    function _returnMoney(Bid memory _bid) private {
        if (_bid.account != address(0) && _bid.value > 0) {
            _transferMoney(_bid.account, _bid.value);
        }
    }

    /// @dev Очищает текущую информацию об аукционе.
    function _clearAuction() private {
        delete _highestBid;
        delete _auction;
    }

    /// @dev Осуществляет перевод нативной валюты блокчейна с адреса контракта.
    function _transferMoney(address to, uint256 value) private {
        (bool success, ) = to.call{value: value}("");

        if (!success) {
            revert TransferMoneyFailed();
        }
    }
}
