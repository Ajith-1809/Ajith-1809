import Card from "./component/Card";

const App = () => {
  return (
    <>
     <div className="outer">
      <Card productName="mobile" price={10000} imagesrc="https://images.pexels.com/photos/1042143/pexels-photo-1042143.jpeg?auto=compress&cs=tinysrgb&w=1260&h=750&dpr=1" />
      <Card productName="laptop" price={50000} imagesrc="https://images.pexels.com/photos/18105/pexels-photo.jpg?auto=compress&cs=tinysrgb&w=1260&h=750&dpr=1" />
      <Card productName="camera" price={40000} imagesrc="https://images.pexels.com/photos/51383/photo-camera-subject-photographer-51383.jpeg?auto=compress&cs=tinysrgb&w=1260&h=750&dpr=1" />
     </div>
    </>
  );
}
export default App;