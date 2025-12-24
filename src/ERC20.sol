// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

contract ERC20 {
    /**
     * @dev Балансы пользователей токена.
     */
    mapping(address => uint256) private _balances;

    /**
     * @dev Разрешения на перевод токенов от имени владельцев.
     */
    mapping(address => mapping(address => uint256)) private _allowances;

    /**
     * @dev Общее количество выпущенных токенов.
     */
    uint256 private _totalSupply;

    /**
     * @dev Имя токена.
     */
    string private _name;

    /**
     * @dev Символ токена.
     */
    string private _symbol;

    /**
     * @dev Устанавливает значения для имени и символа токена.
     * @param name_ Имя токена.
     * @param symbol_ Символ токена.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    // region События

    /**
     * Событие, возникающее при переводе токенов.
     * @param from Адрес отправителя.
     * @param to Адрес получателя.
     * @param value Количество переведенных токенов.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * Событие, возникающее при изменении разрешения на перевод токенов.
     * @param owner Владелец токенов.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     * @param value Количество токенов, на которое предоставлено разрешение.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // region Ошибки

    /**
     * Ошибка при недостаточном балансе для выполнения операции.
     * @param available Количество токенов, доступных на балансе.
     * @param required Количество токенов, необходимых для операции.
     */
    error InsufficientBalance(uint256 available, uint256 required);

    /**
     * Ошибка при недостаточном разрешении на перевод токенов.
     * @param available Количество токенов, доступных по разрешению.
     * @param required Количество токенов, необходимых для операции.
     */
    error InsufficientAllowance(uint256 available, uint256 required);

    /**
     * Ошибка при недопустимом адресе.
     * @param address_ Адрес.
     */
    error InvalidAddress(address address_);

    // region Модификаторы

    /**
     * Модификатор, проверяющий,
     * что у аккаунта достаточно баланса для выполнения операции.
     * @param account Аккаунт, баланс которого проверяется.
     * @param value Количество токенов, необходимых для операции.
     */
    modifier enoughBalance(address account, uint256 value) {
        require(_balances[account] >= value || account == address(0), InsufficientBalance(_balances[account], value));
        _;
    }

    /**
     * Модификатор, проверяющий достаточность разрешения на перевод токенов.
     * @param owner Владелец токенов.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     * @param value Количество токенов, необходимых для операции.
     */
    modifier enoughAllowance(address owner, address spender, uint256 value) {
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= value, InsufficientAllowance(currentAllowance, value));
        _;
    }

    /**
     * Модификатор, проверяющий, что адрес не является нулевым.
     * @param addr Адрес для проверки.
     */
    modifier validAddress(address addr) {
        require(addr != address(0), InvalidAddress(addr));
        _;
    }

    // region Функции.

    /**
     * Получить баланс токенов для указанного аккаунта.
     * @param account Адрес аккаунта.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
     * Получает количество токенов, разрешенных к переводу от имени владельца.
     * @param owner Владелец токенов.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     */
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * Переводит `value` токенов от вызвавшего к адресу `to`.
     * @param to Адрес получателя.
     * @param value Количество токенов для перевода.
     */
    function transfer(address to, uint256 value) public returns (bool) {
        _update(msg.sender, to, value);
        return true;
    }

    /**
     * Переводит `value` токенов от адреса `from` к адресу `to`,
     * используя разрешение, предоставленное `from` вызвавшему.
     * @param from Адрес отправителя.
     * @param to Адрес получателя.
     * @param value Количество токенов для перевода.
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _update(from, to, value);
        return true;
    }

    /**
     * Разрешает `spender` тратить `value` токенов от имени вызвавшего.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     * @param value Количество токенов, на которое предоставлено разрешение.
     */
    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * Устанавливает разрешение на перевод токенов от имени владельца.
     * @param owner Владелец токенов.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     * @param value Количество токенов, на которое предоставлено разрешение.
     */
    function _approve(address owner, address spender, uint256 value)
        internal
        validAddress(owner)
        validAddress(spender)
    {
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * Обновляет балансы и общее количество токенов.
     * @param from Адрес отправителя.
     * @param to Адрес получателя.
     * @param value Количество токенов для перевода.
     */
    function _update(address from, address to, uint256 value) internal enoughBalance(from, value) validAddress(to) {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            unchecked {
                // Переполнение невозможно.
                // Была проверка, что баланс достаточен.
                _balances[from] -= value;
            }
        }

        unchecked {
            // Переполнение невозможно.
            // Вычисляемое значение не превышает _totalSupply.
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    /**
     * Уменьшает разрешение на перевод токенов от имени владельца.
     * @param owner Владелец токенов.
     * @param spender Адрес, которому предоставлено разрешение на перевод токенов.
     * @param value На сколько токенов нужно уменьшить разрешение.
     */
    function _spendAllowance(address owner, address spender, uint256 value)
        internal
        enoughAllowance(owner, spender, value)
    {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            unchecked {
                _approve(owner, spender, currentAllowance - value);
            }
        }
    }

    /**
     * Выпускает `value` новых токенов на адрес `account`.
     * @param account Адрес получателя новых токенов.
     * @param value Количество токенов для выпуска.
     */
    function _mint(address account, uint256 value) internal validAddress(account) {
        _update(address(0), account, value);
    }
}
