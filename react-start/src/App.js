import React, { useState, useEffect } from 'react';
import axios from 'axios';
import AccountCard from './components/AccountCard';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import AccountDetails from "./components/AccountDetails";
import 'bootstrap/dist/css/bootstrap.min.css';

const App = () => {
    const [data, setData] = useState([]);
    const [isScriptRunning, setIsScriptRunning] = useState(localStorage.getItem('isScriptRunning') === 'true');
    const [intervalId, setIntervalId] = useState(null);
    const [page, setPage] = useState(1);
    const [totalPages, setTotalPages] = useState(1);

    const fetchData = async () => {
        try {
            const response = await axios.get(`http://localhost:4567/api/data/page/${page}`);
            setData(response.data.data);
            setTotalPages(response.data.total_pages);
        } catch (error) {
            console.error(error);
        }
    };

    useEffect(() => {
        fetchData();
    }, [page]);

    useEffect(() => {
        localStorage.setItem('isScriptRunning', isScriptRunning);
    }, [isScriptRunning]);

    const runScript = async () => {
        if (!isScriptRunning) {
            setIsScriptRunning(true);
            await axios.post('http://localhost:4567/api/run-script');
            const id = setInterval(fetchData, 10000);
            setIntervalId(id);
        } else {
            setIsScriptRunning(false);
            clearInterval(intervalId);
            await axios.post('http://localhost:4567/api/stop-script');
        }
    };
    const handleNextPage = () => {
        setPage(page + 1);
    };

    const handlePreviousPage = () => {
        setPage(page - 1);
    };

    return (
        <div className="app">
            <Router>
                <Routes>
                    <Route exact path="/" element={
                        <>
                            <button onClick={runScript} className={`btn ${isScriptRunning ? 'btn-danger' : 'btn-success'}`}>
                                {isScriptRunning ? 'Stop Script Parsing' : 'Start Script Parsing'}
                            </button>
                            <AccountCard accounts={data} />
                            <div>
                                {page > 1 && <button onClick={handlePreviousPage} className="btn btn-primary">Previous Page</button>}
                                {page < totalPages && <button onClick={handleNextPage} className="btn btn-primary">Next Page</button>}
                            </div>
                        </>
                    } />
                    <Route path="/account/:username" element={<AccountDetails/>} />
                </Routes>
            </Router>
        </div>
    );
};

export default App;
