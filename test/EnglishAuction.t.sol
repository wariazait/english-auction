// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EnglishAuction} from "../src/EnglishAuction.sol";
import {ERC20} from "../src/ERC20.sol";
import {console} from "forge-std/console.sol";

// Кошелек-получатель, который всегда ревертит при получении ether
contract RevertingReceiver {
    receive() external payable {
        revert("no receive");
    }
}

// Ставит ставку и ревертит при возврате депозита
contract RevertingBidder {
    EnglishAuction public auction;

    constructor(EnglishAuction _auction) {
        auction = _auction;
    }

    function placeBid() external payable {
        auction.bid{value: msg.value}();
    }

    receive() external payable {
        revert("refund failed");
    }
}

contract SomeToken is ERC20 {
    constructor() ERC20("SomeToken", "STK") {
        _mint(msg.sender, 1000000);
    }
}

/// @dev Тесты для смарт-контракта EnglishAuction
contract EnglishAuctionTest is Test {
    EnglishAuction public auction;
    SomeToken public token;

    address owner = makeAddr("owner");

    function setUp() public {
        auction = new EnglishAuction(owner);
        token = new SomeToken();
        token.approve(address(auction), 10);
    }

    /// @dev Тест успешного старта аукциона.
    function testStartAuction() public {
        // Стaртуем аукцион.
        vm.expectEmit(address(auction));
        emit EnglishAuction.AuctionStarted(EnglishAuction.Auction({
                token: token, tokenCount: 10, start: block.timestamp, duration: 0
            }));
        auction.start(token, 10, block.timestamp, 0, 0);

        // Ожидаем, что на адрес контракта пришли разыгрываемые токены.
        assertEq(token.balanceOf(address(auction)), 10);
    }

    /// @dev Тест старта аукциона без разрешения владельца токена ими распоряжаться.
    function testStartAuctionWithoutTokenAllowance() public {
        // Ожидаем получения ошибки, что права на перевод токенов недостаточны.
        vm.expectRevert(EnglishAuction.TokenAllowanceNeeded.selector);

        // Пробуем стартовать аукцион.
        auction.start(token, 11, block.timestamp, 0, 0);
    }

    function testStartAuctionWithoutEnoughTokens() public {
        // Появляется новый токен, созданный другим пользователем.
        address user1 = makeAddr("user1");
        vm.startPrank(user1);
        SomeToken test_token = new SomeToken();
        test_token.approve(address(auction), 10);
        vm.stopPrank();

        // Разрешаем тесту переводить токены.
        test_token.approve(address(this), 10);

        // Ожидаем получения ошибки, что у пользователя недостаточно токенов.
        vm.expectRevert(EnglishAuction.NotEnoughTokens.selector);

        // Пробуем стартовать аукцион.
        auction.start(test_token, 10, block.timestamp, 0, 0);
    }

    /// @dev Тест нескольких ставок от разных пользователей.
    function testMakeBid() public {
        // Создаём тестовых пользователей и пополняем их балансы.
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        vm.deal(user1, 1 ether);
        vm.deal(user2, 2 ether);

        // Запускаем аукцион.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Пользователь 1 делает ставку.
        vm.startPrank(user1);
        vm.expectEmit(address(auction));
        emit EnglishAuction.BidMaked(user1, 1 ether);
        auction.bid{value: 1 ether}();
        vm.stopPrank();

        // Ожидаем, что ставка сделана и денег у пользователя 1 нет.
        EnglishAuction.Bid memory h = auction.getHighestBid();
        assertEq(h.account, user1);
        assertEq(h.value, 1 ether);
        assertEq(user1.balance, 0);

        // Пользователь 2 делает ставку.
        vm.startPrank(user2);
        auction.bid{value: 2 ether}();
        vm.stopPrank();

        // Ожидаем, что ставка сделана и денег у пользователя 2 нет.
        h = auction.getHighestBid();
        assertEq(h.account, user2);
        assertEq(h.value, 2 ether);
        assertEq(user2.balance, 0);

        // Также ожидаем, что пользователь 1 получил свой депозит обратно.
        assertEq(user1.balance, 1 ether);
    }

    /// @dev Тест смены кошелька вывода средств аукциона.
    function testChangeWallet() public {
        // Создаём нового пользователя. Он будет кошельком аукциона.
        address user1 = makeAddr("user1");

        // Обновляем кошелёк смарт-контракта.
        auction.setWallet(user1);

        // Ожидаем, что адрес кошелька аукциона изменился.
        assertEq(auction.getWallet(), user1);
    }

    /// @dev Тест получения информации об аукционе.
    function testGetAuction() public {
        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Ожидаем, что информация об аукционе будет такая-же, которую мы задали при старте.
        EnglishAuction.Auction memory auctionData = auction.getAuction();
        assertEq(address(auctionData.token), address(token));
        assertEq(auctionData.tokenCount, 10);
        assertEq(auctionData.start, block.timestamp);
        assertEq(auctionData.duration, 1 minutes);
    }

    /// @dev Тест отмены аукциона.
    function testCancelAuction() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Пользователь 1 делает ставку.
        vm.startPrank(user1);
        auction.bid{value: 1 ether}();
        vm.stopPrank();

        // Ожидаем, что ставка сделана и денег у пользователя 1 не осталось.
        assertEq(auction.getHighestBid().account, user1);
        assertEq(auction.getHighestBid().value, 1 ether);
        assertEq(user1.balance, 0);

        // Аукцион отменяется.
        vm.expectEmit(address(auction));
        EnglishAuction.Auction memory a = auction.getAuction();
        emit EnglishAuction.AuctionCanceled(a);
        auction.cancel();

        // Ожидаем, что пользователь 1 получил назад свои деньги.
        assertEq(user1.balance, 1 ether);

        // Ожидаем, что аукцион обнулился.
        a = auction.getAuction();
        EnglishAuction.Bid memory h = auction.getHighestBid();
        assertEq(a.start, 0);
        assertEq(a.duration, 0);
        assertEq(address(a.token), address(0));
        assertEq(a.tokenCount, 0);
        assertEq(h.account, address(0));
        assertEq(h.value, 0);

        // Ожидаем, что токен вернулся владельцу.
        assertEq(token.balanceOf(address(this)), 1000000);
        assertEq(token.balanceOf(address(auction)), 0);
    }

    /// @dev Тест штатного завершения аукциона.
    function testFinishAuction() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Пользователь 1 делает ставку.
        vm.startPrank(user1);
        auction.bid{value: 1 ether}();
        vm.stopPrank();

        // Ожидаем, что ставка сделана и денег у пользователя 1 не осталось.
        assertEq(auction.getHighestBid().account, user1);
        assertEq(auction.getHighestBid().value, 1 ether);
        assertEq(user1.balance, 0);

        // Прошло 2 минуты. Аукцион должен успеть завершиться за это время.
        vm.warp(block.timestamp + 2 minutes);

        // Выполняем завершения аукциона.
        EnglishAuction.Auction memory a = auction.getAuction();
        EnglishAuction.Bid memory h = auction.getHighestBid();
        vm.expectEmit(address(auction));
        emit EnglishAuction.AuctionFinished(a, h);
        auction.finish();

        // Ожидаем, что аукцион обнулился
        a = auction.getAuction();
        h = auction.getHighestBid();
        assertEq(a.start, 0);
        assertEq(a.duration, 0);
        assertEq(address(a.token), address(0));
        assertEq(a.tokenCount, 0);
        assertEq(h.account, address(0));
        assertEq(h.value, 0);

        // Ожидаем, что на кошелёк владельца аукциона пришла ставка.
        assertEq(owner.balance, 1 ether);

        // Ожидаем, что победителю пришли токены.
        assertEq(token.balanceOf(user1), 10);
        assertEq(token.balanceOf(address(auction)), 0);
    }

    /// @dev Тест штатного завершения аукциона, который прошёл без ставок.
    function testFinishAuctionWithoutBids() public {
        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Прошло 2 минуты. Аукцион должен успеть завершиться за это время.
        vm.warp(block.timestamp + 2 minutes);

        // Выполняем завершения аукциона.
        EnglishAuction.Auction memory a = auction.getAuction();
        EnglishAuction.Bid memory h = auction.getHighestBid();
        vm.expectEmit(address(auction));
        emit EnglishAuction.AuctionFinished(a, h);
        auction.finish();

        // Ожидаем, что аукцион обнулился
        a = auction.getAuction();
        h = auction.getHighestBid();
        assertEq(a.start, 0);
        assertEq(a.duration, 0);
        assertEq(address(a.token), address(0));
        assertEq(a.tokenCount, 0);
        assertEq(h.account, address(0));
        assertEq(h.value, 0);

        // Ожидаем, что токен вернулся владельцу.
        assertEq(token.balanceOf(address(this)), 1000000);
        assertEq(token.balanceOf(address(auction)), 0);
    }

    /// @dev Тест старта аукциона, который уже запущен.
    function testStartAlreadyStartedAuction() public {
        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Происходит попытка стартовать аукцион во время проведения другого.
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.AuctionAlreadyStarted.selector);
        auction.start(token, 10, block.timestamp + 1 minutes, 1 minutes, 1 ether);
    }

    /// @dev Тест ставки в незапущенном аукционе.
    function testBidOnStoppedAuction() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Пользователь 1 пытается сделать ставку.
        vm.startPrank(user1);
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.AuctionNotStarted.selector);
        auction.bid{value: 1 ether}();
        vm.stopPrank();
    }

    /// @dev Тест ставки до начала аукциона.
    function testBidBeforeAuctionStarts() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Задаём отложенный старт аукциона минутой позже текущего времени.
        auction.start(token, 10, block.timestamp + 1 minutes, 1 minutes, 0);

        // Пользователь 1 пытается сделать ставку.
        vm.startPrank(user1);
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.AuctionNotStarted.selector);
        auction.bid{value: 1 ether}();
        vm.stopPrank();
    }

    /// @dev Тест создания аукциона с нулевым кошельком владельца.
    function testCreateAuctionWithZeroOwner() public {
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.WalletAddressZero.selector);
        new EnglishAuction(address(0));
    }

    /// @dev Тест старта аукциона "задним числом".
    function testCreateAuctionBeforeTransactionTime() public {
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.TooEarlyStartTime.selector);

        // Перематываем текущее время на 2 минуты.
        vm.warp(2 minutes);

        // Пытаемся создать аукцион "задним числом" со стартом минуту назад.
        auction.start(token, 10, block.timestamp - 1 minutes, 1 minutes, 0);
    }

    /// @dev Тест ставки не перебивающей текущую стоимость.
    function testBidNotEnoughMoney() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 2 ether);

        // Пользователь 1 пытается сделать ставку ниже стартовой стоимости.
        vm.startPrank(user1);
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.NotEnoughMoney.selector);
        auction.bid{value: 1 ether}();
        vm.stopPrank();
    }

    /// @dev Тест ставки после завершения аукциона.
    function testBidAfterAuctionFinished() public {
        // Создаём пользователя для ставки.
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);

        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // Прошло 2 минуты. Время аукциона закончилось.
        vm.warp(block.timestamp + 2 minutes);

        // Пользователь 1 пытается делать ставку.
        vm.startPrank(user1);
        // Ожидаем ошибку.
        vm.expectRevert(EnglishAuction.AuctionAlreadyFinished.selector);
        auction.bid{value: 1 ether}();
        vm.stopPrank();
    }

    /// @dev Тест завершения аукциона раньше времени.
    function testFinishAuctionBeforeTime() public {
        // Аукцион стартует.
        auction.start(token, 10, block.timestamp, 1 minutes, 0);

        // При попытке завершить аукцион ожидаем ошибку, так как время ещё не прошло.
        vm.expectRevert(EnglishAuction.AuctionNotFinished.selector);
        auction.finish();
    }

    /// @dev Тест сбоя перевода средств на кошелёк аукциона.
    function testFinish_TransferToWalletFails() public {
        // Старт аукциона
        auction.start(token, 10, block.timestamp, 1 hours, 0);

        // Ставка от EOA
        address user = address(0x1);
        vm.deal(user, 1 ether);
        vm.prank(user);
        auction.bid{value: 1 ether}();

        // Делаем кошелек "плохим" получателем
        RevertingReceiver badWallet = new RevertingReceiver();
        auction.setWallet(address(badWallet));

        // Завершаем после окончания и ожидаем реверт TransferMoneyFailed
        vm.warp(block.timestamp + 1 hours + 1);
        vm.expectRevert(EnglishAuction.TransferMoneyFailed.selector);
        auction.finish();
    }

    /// @dev Тест сбоя возврата средств за предыдущую ставку.
    function testBid_RefundPreviousBidderFails() public {
        // Старт аукциона
        auction.start(token, 10, block.timestamp, 1 hours, 0);

        // Первый лидер — контракт, который ревертит при возврате
        RevertingBidder badBidder = new RevertingBidder(auction);
        // Отправляем ему средства и делаем ставку
        badBidder.placeBid{value: 1 ether}();

        // Второй участник пытается перебить — возврат предыдущему лидеру зафейлится
        address user2 = address(0x2);
        vm.deal(user2, 2 ether);
        vm.prank(user2);
        vm.expectRevert(EnglishAuction.TransferMoneyFailed.selector);
        auction.bid{value: 2 ether}();
    }
}
