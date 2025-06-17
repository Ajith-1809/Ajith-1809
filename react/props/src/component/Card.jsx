    const Card = (props) => {
  return (
    <>
    <div className="card">
        <img src={props.imagesrc} alt={props.productName} />
      <h2>Product Name: {props.productName}</h2>
      <p>Price: {props.price}</p>
    </div>
    </>
  );
}

export default Card;
