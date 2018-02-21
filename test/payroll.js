const Payroll = artifacts.require('./Payroll.sol')
const StandardToken = artifacts.require('./token/StandardToken')
const { increaseTime } = require('./helpers/web3.js')

contract('Payroll', accounts => {
    const oneHour = 60 * 60
    const oneDay = oneHour * 24
    const oneMonth = oneDay * 30
    const sixMonths = oneMonth * 6

    let token1 = {}
    let token2 = {}

    let payroll = {}
    let payrollOwner = accounts[0]
    let employee1 = accounts[1]
    let employee2 = accounts[2]
    let employee1ID = {}
    let employee2ID = {}
    let oracle = accounts[3]
    let baseSalary = 12000
    let baseDistribution = [100, 0, 0]
    let tokens = ["0x000000000000000000000000000000000000000"]

    before('create tokens', async () => {
        token1 = await StandardToken.new()
        token2 = await StandardToken.new()

        tokens.push(token1.address)
        tokens.push(token2.address)

        await token1.mint(100000, {from: payrollOwner})
        await token2.mint(100000, {from: payrollOwner})

        assert.equal(await token1.balanceOf(payrollOwner), 100000, 'payroll owner should have 100000 token1')
        assert.equal(await token2.balanceOf(payrollOwner), 100000, 'payroll owner should have 100000 token1')
    })

    beforeEach('create payroll', async () => {
        payroll = await Payroll.new(oracle, {from: payrollOwner})
        assert.ok(payroll)

        assert.ok(await payroll.setExchangeRate(tokens[0], 1, {from: oracle}))
        assert.ok(await payroll.setExchangeRate(tokens[1], 1, {from: oracle}))
        assert.ok(await payroll.setExchangeRate(tokens[2], 1, {from: oracle}))
    })

    context('Funding', async () => {
        it('add ether funds to payroll', async () => {
            await payroll.addFunds({from: payrollOwner, value: 100000})

            let funds = await payroll.getPayrollFunds({from: payrollOwner})
            assert.equal(funds.toNumber(), 100000, 'payroll should have a value of $100000 in it')
        })

        it('add token funds to payroll', async () => {
            await token1.approve(payroll.address, 100000, {from: payrollOwner})
            let balance = await token1.allowance(payrollOwner, payroll.address)
            assert.equal(balance.toNumber(), 100000, 'payroll should have allowance of 100000 of token1')

            await token2.approve(payroll.address, 100000, {from: payrollOwner})
            balance = await token2.allowance(payrollOwner, payroll.address)
            assert.equal(balance.toNumber(), 100000, 'payroll should have 100000 of token2')
        })

        it('reset initial exchange rate', async () => {
            await payroll.setExchangeRate(tokens[0], 2, {from: oracle})

            await payroll.addFunds({from: payrollOwner, value: 100000})

            let funds = await payroll.getPayrollFunds({from: payrollOwner})
            assert.equal(funds.toNumber(), 200000, 'payroll should have a value of $200000 in it')
        })

        it('exchange rate increases', async () => {
            await payroll.addFunds({from: payrollOwner, value: 100000})

            let funds = await payroll.getPayrollFunds({from: payrollOwner})
            assert.equal(funds.toNumber(), 100000, 'payroll should have a value of $100000 in it')

            await payroll.setExchangeRate(tokens[0], 2, {from: oracle})

            funds = await payroll.getPayrollFunds({from: payrollOwner})
            assert.equal(funds.toNumber(), 200000, 'payroll should have a value of $200000 in it')
        })

        it('escape hatch', async () => {
            assert.ok(await payroll.scapeHatch())
        })
    })

    context('Employees', async () => {
        beforeEach('add employees to payroll', async () => {
            await payroll.addFunds({from: payrollOwner, value: 100000})

            let funds = await payroll.getPayrollFunds({from: payrollOwner})
            assert.equal(funds.toNumber(), 100000, 'payroll should have a value of $100000 in it')

            await payroll.addEmployee(employee1, tokens, baseDistribution, baseSalary, {from: payrollOwner})
            let employeeCount = await payroll.getEmployeeCount()
            assert.equal(employeeCount.toNumber(), 1, 'Should be 1 employees on payroll')

            let employee2Distrobution = [50, 25, 25]
            await payroll.addEmployee(employee2, tokens, employee2Distrobution, baseSalary, {from: payrollOwner})
            employeeCount = await payroll.getEmployeeCount()
            assert.equal(employeeCount.toNumber(), 2, 'Should be 2 employees on payroll')
        })

        it('get employee info', async () => {
            let emp1 = await payroll.getEmployee(0, {from: payrollOwner})
            assert.equal(emp1[0], 0, 'last payday should be 0')
            assert.equal(emp1[1], 0, 'last allocated should be 0')
            assert.equal(emp1[2], baseSalary, 'employees salary should be' + baseSalary)
        })

        it('reverts with invalid employee id', async () => {
            try {
                await payroll.getEmployee(-1, {from: payrollOwner})
            } catch(e) {
                assert.isAbove(e.message.search('opcode'), -1, 'expected a invalid opcode')
            }
        })

        it('remove employee', async () => {
            await payroll.removeEmployee(0)

            let employeeCount = await payroll.getEmployeeCount()
            assert.equal(employeeCount.toNumber(), 1, 'should only be one employee on payroll')
        })

        it('set employees new salary', async () => {
            const newSalary = baseSalary + 10000
            await payroll.setEmployeeSalary(0, newSalary, {from: payrollOwner})
            let emp1 = await payroll.getEmployee(0, {from: payrollOwner})
            assert.equal(emp1[2], newSalary, 'employee salary should now be 22000')
        })

        context('Payments and Burnrates', async () => {
            beforeEach('approve some tokens for spending', async () => {
                await token1.approve(payroll.address, 100000, {from: payrollOwner})
                let balance = await token1.allowance(payrollOwner, payroll.address)
                assert.equal(balance.toNumber(), 100000, 'payroll should have allowance of 100000 of token1')

                await token2.approve(payroll.address, 100000, {from: payrollOwner})
                balance = await token2.allowance(payrollOwner, payroll.address)
                assert.equal(balance.toNumber(), 100000, 'payroll should have 100000 of token2')
            })

            it('employee paydays', async () => {
                // pay employee 1 and confirm that funds have been moved
                await payroll.payday({from: employee1})
                let currentFunds = await payroll.getPayrollFunds({from: payrollOwner})
                assert.equal(currentFunds.toNumber(), 99000, 'Payroll should only have $99000 in ether funds after employee payment')

                // pay employee2 and confirm that funds have been moved
                await payroll.payday({from: employee2})
                currentFunds = await payroll.getPayrollFunds({from: payrollOwner})
                assert.equal(currentFunds.toNumber(), 98500, 'Payroll should only have $98500 in ether funds after employee payment')
            })

            it('calculate payroll burnrate', async () => {
                let burnrate = await payroll.calculatePayrollBurnrate()

                assert.equal(burnrate.toNumber(), 2000, 'current burn rate should be only $2000/month')
            })

            it('days we have remaining for funds', async () => {
                let runway = await payroll.calculatePayrollRunway()

                assert.equal(runway.toNumber(), 1538, 'Should have 1538 days left for payroll until funds are depleted')
            })

            it('fails if calls payday again before a month', async () => {
                await payroll.payday({from: employee1})

                try {
                    await payroll.payday({from: employee1})
                } catch (e) {
                    return assert.isAbove(e.message.search('revert'), -1, 'expected a revert from truffle')
                }
                assert.fail('should have reverted')
            })

            it('can call payday after one month', async () => {
                await payroll.payday({from: employee1})

                await increaseTime(oneMonth + oneHour)

                await payroll.payday({from: employee1})
            })
        })

        context('Token Allocation', async () => {
            it('allocate tokens', async () => {
                let distribution = [75, 15, 10]
                await payroll.determineAllocation(tokens, distribution, {from: employee1})

                let emp1 = await payroll.getEmployee(0, {from: payrollOwner})
                assert.equal(emp1[4][0], distribution[0], 'Employee1 token0 (ether) distribution should be 75')
                assert.equal(emp1[4][1], distribution[1], 'Employee1 token1 distribution should be 15')
                assert.equal(emp1[4][2], distribution[2], 'Employee1 token2 distribution should be 10')
            })

            it('fails with invalid token distribution', async () => {
                // check that we fail on an invalid distribution of tokens
                try {
                    let distribution = [75, 20, 10]
                    await payroll.determineAllocation(tokens, distribution, {from: employee1})
                } catch (e) {
                    assert.isAbove(e.message.search('revert'), -1, 'expected a revert from truffle')
                }
            })

            it('fails if allocates again before 6 months', async () => {
                let distribution = [75, 15, 10]
                await payroll.determineAllocation(tokens, distribution, {from: employee1})

                // check that the employee cannot call again until another 6 months
                try {
                    await payroll.determineAllocation(tokens, distribution, {from: employee1})
                } catch (e) {
                    return assert.isAbove(e.message.search('revert'), -1, 'expected a revert from truffle')
                }
                assert.fail('should have reverted')
            })

            it('can allocate after 6 months', async () => {
                let distribution = [75, 15, 10]
                await payroll.determineAllocation(tokens, distribution, {from: employee1})

                // let's time travel 6 months in the future
                await increaseTime(sixMonths + oneHour)

                await payroll.determineAllocation(tokens, distribution, {from: employee1})
            })
        })
    })
})
