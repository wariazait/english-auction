// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract EnglishAuction is Ownable {
    struct Auction {
        string itemDescription;
        uint256 start;
        uint256 duration;
    }

    struct HighestBid {
        address account;
        uint256 value;
    }

    Auction private _auction;
    HighestBid private _highestBid;
    address private _wallet;

    event WalletSet(address wallet);
    event AuctionStarted(Auction auction);
    event AuctionCanceled(Auction auction);
    event AuctionFinished(Auction auction, HighestBid bid);
    event Bid(address account, uint256 value);

    error WalletAddressZero();
    error TooEarlyStartTime();
    error AuctionAlreadyStarted();
    error AuctionAlreadyFinished();
    error AuctionNotFinished();
    error AuctionNotStarted();
    error NotEnoughMoney();
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
     * @param _itemDescription Описание продаваемой сущности.
     * @param startTime Время начала аукциона.
     * @param _duration Длительность аукциона.
     * @dev Аукцион можно начать заранее, указав соответствующее время начала.
     */
    function start(
        string memory _itemDescription,
        uint256 startTime,
        uint256 _duration,
        uint256 startPrice
    ) external onlyOwner {
        require(_auction.start == 0, AuctionAlreadyStarted());
        require(startTime >= block.timestamp, TooEarlyStartTime());

        _auction = Auction({
            itemDescription: _itemDescription,
            start: startTime,
            duration: _duration
        });

        _highestBid = HighestBid({account: address(0), value: startPrice});

        emit AuctionStarted(_auction);
    }

    /// @notice Позволяет сделать ставку.
    function bid() external payable whenStarted {
        require(
            block.timestamp < _auction.start + _auction.duration,
            AuctionAlreadyFinished()
        );
        require(msg.value > _highestBid.value, NotEnoughMoney());

        HighestBid memory currentBid = _highestBid;
        _highestBid = HighestBid({account: msg.sender, value: msg.value});
        _returnMoney(currentBid);

        emit Bid(msg.sender, msg.value);
    }

    /**
     * @notice Отменяет аукцион.
     * @dev Отменить аукцион может только его владелец и только после старта.
     */
    function cancel() external whenStarted onlyOwner {
        Auction memory auction = _auction;
        HighestBid memory currentBid = _highestBid;

        _clearAuction();
        _returnMoney(currentBid);

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
        HighestBid memory highestBid = _highestBid;

        _clearAuction();

        if (highestBid.account != address(0)) {
            _transferMoney(_wallet, highestBid.value);
        }

        emit AuctionFinished(auction, highestBid);
    }

    /// @notice Возвращает информацию о текущей наибольшей ставке.
    function getHighestBid() external view returns (HighestBid memory) {
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
    function _returnMoney(HighestBid memory _bid) private {
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
