import React, { useState } from 'react'

const App = () => {

  let num = 20
  let mynum = ()=>{
    num = num + 1
    console.log(num);
  }

  let [number, setNumber] = useState(20)
  let increase =()=>{
    setNumber(number + 1)
    console.log(number);
  }

  let decrease =()=>{
    setNumber(number - 1)
    console.log(number);
  }
  return (
    <>
      <h1>{num}</h1>
      <button onClick={mynum}>click</button>

      <h1>Number is : {number}</h1>
      <button onClick={increase}>increase</button>
      <button onClick={decrease}>decrease</button>
      <button onClick={()=>setNumber(number / 10)}>decrease2</button>
      <button onClick={()=>setNumber(number * 10)}>increase2</button>
    </>
  )
}

export default App