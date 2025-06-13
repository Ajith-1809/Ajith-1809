import Card from "./Card";
import Navbar from "./Navbar";
let Home = () => {
    return (
        <>
        <div>
        <Navbar />
        <div className="home">
        <h1>Welcome to My Home Page</h1>
        </div>
        </div>
        <div className="card-container">
            <Card />
            <Card />
            <Card />
        </div>
        </>
    );
}

export default Home;