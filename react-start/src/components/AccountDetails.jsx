import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import axios from "axios";
import { Link } from 'react-router-dom';

const fetchData = async (username) => {
    try {
        let url = `http://localhost:4567/api/data/account/${username}`
        const response = await axios.get(url);
        return response.data;
    } catch (error) {
        console.error(error);
    }
};

const AccountDetails = () => {
    let { username } = useParams();
    const [userData, setUserData] = useState(null);
    useEffect(() => {
        const fetchUserData = async () => {
            const data = await fetchData(username);
            setUserData(data);
        };
        fetchUserData();
    }, [username]);

    return (
        <div className="container mt-5">
            <Link to="/" className="btn btn-primary mt-3">Back</Link>
            <h2 className="text-center">Account Details for {username}</h2>
            <div className="row justify-content-center">
                <div className="col-md-6">
                    <div className="card">
                        <div className="card-body">
                            {userData && (
                                <div>
                                    <h3>Last Best Post</h3>
                                    <p><strong>Post Link:</strong> <a href={userData.postlink} target="_blank">{userData.postlink}</a></p>
                                    <p><strong>Title:</strong> {userData.title}</p>
                                    <p><strong>Comment:</strong> {userData.comment}</p>
                                    <p><strong>Views:</strong> {userData.view}</p>
                                    <p><strong>Posted At:</strong> {userData.postedat}</p>
                                    <p><strong>Description:</strong> {userData.description}</p>
                                </div>
                            )}
                        </div>
                    </div>
                </div>
                <div className="col-md-6">
                    <div className="card">
                        <img src={userData && userData.originprofilepicture} alt={userData && userData.username} className="card-img-top"/>
                        <div className="card-body">
                            <p><strong>Name:</strong> <a href={`https://www.youtube.com/@${userData && userData.username}`} target="_blank">{userData && userData.username}</a></p>
                            <p><strong>Email:</strong> {userData && userData.email}</p>
                            <p><strong>Biography:</strong> {userData && userData.biography}</p>
                            <p><strong>Country:</strong> {userData && userData.country}</p>
                            <p><strong>Followers:</strong> {userData && userData.followers}</p>
                            <p><strong>Views:</strong> {userData && userData.views}</p>
                            <p><strong>Posts:</strong> {userData && userData.posts}</p>
                            <p><strong>Hashtags:</strong> {userData && userData.hashtags}</p>
                            <p><strong>Gender:</strong> {userData && userData.gender}</p>
                            <p><strong>Verified:</strong> {userData && userData.is_verified}</p>
                            <p><strong>Language:</strong> {userData && userData.language}</p>
                            <p><strong>Business Email Exist:</strong> {userData && userData.is_business_email_exist}</p>
                            <p><strong>Ages:</strong> {userData && userData.ages}</p>
                            <p><strong>Title:</strong> {userData && userData.title}</p>
                            <p><strong>Engagement Rate:</strong> {userData && userData.engagementrate}</p>
                            <p><strong>Average Views:</strong> {userData && userData.averageviews}</p>
                            <p><strong>Total Engagement:</strong> {userData && userData.totalengagement}</p>
                            <p><strong>Average Comments:</strong> {userData && userData.averagecomments}</p>
                            <p><strong>Average Dislikes:</strong> {userData && userData.averagedislikes}</p>
                            <p><strong>Average Likes:</strong> {userData && userData.averagelikes}</p>
                            <p><strong>Post Interval:</strong> {userData && userData.postinterval}</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default AccountDetails;