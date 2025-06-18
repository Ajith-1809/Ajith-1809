import React from 'react'

const App = () => {
  let display = ()=>{
    alert("this is event.....")
  }
  let wish = (name)=>{
    alert("hii  "+name)
  }
  return (
    <>
    <h1>I am App component</h1>
    <button onClick={display}>click</button>
    <button onClick={()=>display()}>click me</button>
    <button onClick={()=>wish("dhoni")}>greetings</button>
    </>
  )
}

export default App