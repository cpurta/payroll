pragma solidity ^0.4.18;

import "./PayrollInterface.sol";
import "./math/SafeMath.sol";
import "./token/StandardToken.sol";


contract Payroll is PayrollInterface {
    using SafeMath for uint256;

    struct Employee {
        uint lastPayday;
        uint lastAllocated;
        uint256 yearlySalaryUSD;
        address[] tokenAllocation;
        uint256[] tokenDistribution;
    }

    address private owner;
    address private oracle;

    Employee[] employees;
    mapping (address => uint256) employmentHistory;

    uint256 private totalFundsUSD;
    mapping (address => uint256) private tokenFunds;
    mapping (address => uint256) private exchangeRates;


    event EmployeeAdded(address _employee, address[] _allowedTokens, uint256 _initialYearlySalary);
    event EmployeeSalaryChanged(uint256 employeeId, uint256 _yearlyUSDSalary);
    event EmployeeRemoved(uint256 employeeId);
    event FundsAdded(address token, uint256 amount, uint256 currentFunds);
    event TokensAllocated(address employee, address[] tokens, uint256[] distribution);
    event TransferedEther(address employee, uint256 amount);
    event TransferedToken(address employee, address token, uint256 amount);
    event EmployeePaid(address employee, uint256 amount);
    event ExchangeRateSet(address token, uint256 exchangeRate);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyEmployed() {
        require(employees[employmentHistory[msg.sender]].yearlySalaryUSD > 0);
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle);
        _;
    }

    /**
     * @dev Payroll creates a new payroll with the sender being the owner of the payroll
     * @param _oracle
     */
    function Payroll(address _oracle) public {
        owner = msg.sender;
        oracle = _oracle;
    }

    /**
     * @dev addEmployee allows the payroll owner to add a employee to the payroll
     * @param accountAddress is the address of the employee being added to the payroll
     * @param allowedTokens is an array of the tokens that the employee is allowed to be paid in
     * @param distribution is an array of percentages that add to 100 specifying what percent of the employee salary will be paid out in each token
     * @param initialYearlyUSDSalary is the yearly USD salary of the employee
     */
    function addEmployee(address accountAddress, address[] allowedTokens, uint256[] distribution, uint256 initialYearlyUSDSalary) public onlyOwner {
        require(accountAddress != 0x0);
        require(allowedTokens.length == distribution.length);
        require(initialYearlyUSDSalary >= 0);

        employmentHistory[accountAddress] = employees.length;

        employees.push(Employee({
            lastPayday: 0,
            lastAllocated: 0,
            yearlySalaryUSD: initialYearlyUSDSalary,
            tokenAllocation: allowedTokens,
            tokenDistribution: distribution
        }));
        EmployeeAdded(accountAddress, allowedTokens, initialYearlyUSDSalary);
    }
    /**
     * @dev setEmployeeSalary allows the payroll owner to increase or decrease an employee salary
     * @param _employeeId numerical id of the employee must be greater than -1
     * @param _yearlyUSDSalary new salary of the employee must be greater than 0
     */
    function setEmployeeSalary(uint256 _employeeId, uint256 _yearlyUSDSalary) public onlyOwner {
        require(employees[_employeeId].yearlySalaryUSD > 0 && _yearlyUSDSalary > 0);

        employees[_employeeId].yearlySalaryUSD = _yearlyUSDSalary;
        EmployeeSalaryChanged(_employeeId, _yearlyUSDSalary);
    }

    /**
     * @dev removeEmployee allows for the payroll owner to remove an employee from payroll
     * @param _employeeId numerical id of the employee must be greater than -1
     */
    function removeEmployee(uint256 _employeeId) public onlyOwner {
        require(employees[_employeeId].yearlySalaryUSD > 0);

        // use delete so that employee id order is preserved
        delete employees[_employeeId];

        employees.length--;
        EmployeeRemoved(_employeeId);
    }

    /**
     * @dev addFunds allows the payroll owner to add ether funds to the payroll
     */
    function addFunds() public onlyOwner payable {
        require(msg.value > 0);
        uint256 fundsUSD = msg.value.mul(exchangeRates[0x0]);
        totalFundsUSD = totalFundsUSD.add(fundsUSD);
        FundsAdded(0x0, fundsUSD, totalFundsUSD);
    }

    /**
     * @dev scapeHatch allows the owner to take funds so that they are not lost in the contract forever
     */
    function scapeHatch() public onlyOwner {
        selfdestruct(owner);
    }

    /**
     * @dev getPayrollFunds returns the ether funds in USD
     * @notice only the payroll owner can call this function
     */
    function getPayrollFunds() public view onlyOwner returns (uint256) {
        return this.balance.mul(exchangeRates[0x0]);
    }

    /**
     * @dev getEmployeeCount returns the current number of employee on payroll
     */
    function getEmployeeCount() public view returns (uint256) { return employees.length; }

    /**
     * @dev getEmployee returns information about the employee using their employeeID
     * @param _employeeId numerical id of employee on payroll, must be greater than -1
     */
    function getEmployee(uint256 _employeeId) public view returns (uint, uint, uint256, address[], uint256[]) {
        require(_employeeId >= 0);
        Employee storage employee = employees[_employeeId];
        return (
            employee.lastPayday,
            employee.lastAllocated,
            employee.yearlySalaryUSD,
            employee.tokenAllocation,
            employee.tokenDistribution);
    }

    /**
     * @dev _calculateYearlyBurnrate determines the how much funds are spent per year
     */
    function _calculateYearlyBurnrate() internal view returns (uint256) {
        uint256 yearlyBurnrate;
        for (uint256 i = 0; i < employees.length; i++) {
            yearlyBurnrate = yearlyBurnrate.add(employees[i].yearlySalaryUSD);
        }
        return yearlyBurnrate;
    }

    /**
     * @dev calculatePayrollBurnrate determines how much funds are spent per month
     */
    function calculatePayrollBurnrate() public view returns (uint256) {
        return _calculateYearlyBurnrate().div(uint256(12));
    }

    /**
     * @dev calculatePayrollRunway calculates how manys days are left until the payroll is out of funds
     */
    function calculatePayrollRunway() public view returns (uint256) {
        uint256 dailyBurnRate = _calculateYearlyBurnrate().div(uint256(365));
        return totalFundsUSD.div(dailyBurnRate);
    }

    /**
     * @dev determineAllocation lets a employee determine which tokens they would like to be paid in and in what distribution
     * @notice only employees can call this function and can only do so every six months
     * @notice distribution array values must add up to 100
     * @param tokens array of tokens that the employee wishes to be paid out in
     * @param distribution array of percentages of how the employee will be paid out in each token
     */
    function determineAllocation(address[] tokens, uint256[] distribution) onlyEmployed public {
        require(tokens.length > 0 && tokens.length == distribution.length);
        require(block.timestamp > employees[employmentHistory[msg.sender]].lastAllocated + 180 * 1 days);

        uint256 totalDistribution;
        for (uint256 i = 0; i < distribution.length; i++) {
            totalDistribution = totalDistribution.add(distribution[i]);
        }

        require(totalDistribution == 100);
        employees[employmentHistory[msg.sender]].tokenAllocation = tokens;
        employees[employmentHistory[msg.sender]].tokenDistribution = distribution;
        employees[employmentHistory[msg.sender]].lastAllocated = block.timestamp;

        TokensAllocated(msg.sender, tokens, distribution);
    }

    /**
     * @dev payday allows for employees to collect their monthly paycheck
     * @notice Only employees can call this function and can only call this once every 30 days
     */
    function payday() onlyEmployed public {
        require(employees[employmentHistory[msg.sender]].yearlySalaryUSD > 0);

        Employee storage employee = employees[employmentHistory[msg.sender]];

        require(block.timestamp > employee.lastPayday + 30 * 1 days);
        uint256 monthPaycheckUSD = employee.yearlySalaryUSD.div(uint256(12));

        for (uint256 i = 0; i < employee.tokenAllocation.length; i++) {
            // determine the amount in the token we should be paying to the employee
            address token = employee.tokenAllocation[i];
            uint256 distribution = employee.tokenDistribution[i];
            if (distribution == 0) {
                continue;
            }

            uint256 tokenPaycheckUSD = (monthPaycheckUSD.mul(distribution)).div(uint(100));
            uint256 tokenPaycheck = tokenPaycheckUSD.div(exchangeRates[token]);
            if (token == 0x0) {
                // just do an ether transfer
                msg.sender.transfer(tokenPaycheck);
                TransferedEther(msg.sender, tokenPaycheck);
            } else {
                // will need to use ERC20 transfer protocols
                StandardToken stdToken = StandardToken(token);
                stdToken.transferFrom(owner, msg.sender, tokenPaycheck);
                TransferedToken(msg.sender, token, tokenPaycheck);
            }
        }

        totalFundsUSD = totalFundsUSD.sub(monthPaycheckUSD);
        employee.lastPayday = block.timestamp;
        EmployeePaid(msg.sender, monthPaycheckUSD);
    }

    /**
     * @dev setExchangeRate allows for a token oracle to set the exchange rate of tokens handed out in payroll
     * @param _token address of the token
     * @param _usdExchangeRate exchange rate of the token in USD/token
     */
    function setExchangeRate(address _token, uint256 _usdExchangeRate) public onlyOracle {
        require(msg.sender == oracle && _usdExchangeRate > 0);
        exchangeRates[_token] = _usdExchangeRate;
        ExchangeRateSet(_token, _usdExchangeRate);
    }
}
