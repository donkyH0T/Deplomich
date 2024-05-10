import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import axios from 'axios';

const AccountCard = ({ initialAccounts }) => {
    const [accounts, setAccounts] = useState([]);
    const [searchValue, setSearchValue] = useState('');
    const [sortType, setSortType] = useState(null);
    const [sortDirection, setSortDirection] = useState('asc');

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        const response = await axios.get(`http://localhost:4567/api/accounts?sort=${sortType}&direction=${sortDirection}&search=${searchValue}`);
        //console.log(response.data)
        setAccounts(response.data);
    };

    useEffect(() => {
        if (initialAccounts.length > 0) {
            setAccounts(initialAccounts);
        }
    }, [initialAccounts]);

    const handleSort = (type) => {
        if (type === sortType) {
            setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
        } else {
            setSortType(type);
            setSortDirection('asc');
        }
    };
    const handleSubmit = (e) => {
        e.preventDefault();
        fetchData();
    }
    //console.log(accounts)
    return (
        <div>
            <form onSubmit={handleSubmit}>
                <input
                    type="text"
                    placeholder="Find by username"
                    value={searchValue}
                    onChange={(e) => setSearchValue(e.target.value)}
                    className="form-control mb-3"
                />
                <button type="submit">Search</button>
            </form>
            <table className="table">
                <thead className="thead-dark">
                <tr>
                    <th onClick={() => { handleSort('username'); fetchData(); }}>Username {sortType === 'username' && (sortDirection === 'asc' ? '↑' : '↓')}</th>
                    <th onClick={() => { handleSort('followers'); fetchData(); }}>Followers {sortType === 'followers' && (sortDirection === 'asc' ? '↑' : '↓')}</th>
                    <th>Img</th>
                    <th>More details</th>
                </tr>
                </thead>
                <tbody>
                {accounts && accounts.length > 0 && accounts.map(account => (
                    <tr key={account.username}>
                        <td>{account.username}</td>
                        <td>{account.followers}</td>
                        <td><img src={account.originprofilepicture} alt={account.username} style={{ width: '50px', borderRadius: '50%' }} /></td>
                        <td><Link to={`/account/${account.username}`}>More details</Link></td>
                    </tr>
                ))}
                </tbody>
            </table>
        </div>
    );
};

export default AccountCard;
