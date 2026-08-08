import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API_BASE = "http://127.0.0.1:8000";

function App() {
  const [employees, setEmployees] = useState([]);
  const [form, setForm] = useState({ name: '', email: '', department: '', salary: '' });
  const [loading, setLoading] = useState(false);

  const fetchEmployees = async () => {
    try {
      const res = await axios.get(`${API_BASE}/employees`);
      setEmployees(res.data);
    } catch (err) { console.error("Error fetching employees", err); }
  };

  useEffect(() => { fetchEmployees(); }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await axios.post(`${API_BASE}/employees`, {
        name: form.name, email: form.email, department: form.department, salary: parseFloat(form.salary)
      });
      setForm({ name: '', email: '', department: '', salary: '' });
      fetchEmployees();
    } catch (err) {
      alert("Error adding employee: " + (err.response?.data?.detail || err.message));
    } finally { setLoading(false); }
  };

  const handleDelete = async (id) => {
    if (window.confirm("Are you sure you want to delete this employee?")) {
      try {
        await axios.delete(`${API_BASE}/employees/${id}`);
        fetchEmployees();
      } catch (err) { alert("Error deleting employee"); }
    }
  };

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '30px', maxWidth: '900px', margin: '0 auto', background: '#f8f9fa', minHeight: '100vh' }}>
      <header style={{ textAlign: 'center', marginBottom: '30px' }}>
        <h1 style={{ color: '#333' }}>Enterprise Employee Management System</h1>
        <p style={{ color: '#666' }}>FastAPI + LocalStack DynamoDB + React</p>
      </header>

      <div style={{ background: '#fff', padding: '20px', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)', marginBottom: '30px' }}>
        <h2>Add New Employee</h2>
        <form onSubmit={handleSubmit} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <input type="text" placeholder="Full Name" value={form.name} onChange={e => setForm({...form, name: e.target.value})} required style={{ padding: '10px' }} />
          <input type="email" placeholder="Email Address" value={form.email} onChange={e => setForm({...form, email: e.target.value})} required style={{ padding: '10px' }} />
          <input type="text" placeholder="Department" value={form.department} onChange={e => setForm({...form, department: e.target.value})} required style={{ padding: '10px' }} />
          <input type="number" placeholder="Salary ($)" value={form.salary} onChange={e => setForm({...form, salary: e.target.value})} required style={{ padding: '10px' }} />
          <button type="submit" disabled={loading} style={{ gridColumn: 'span 2', padding: '12px', background: '#007bff', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>
            {loading ? "Saving..." : "Add Employee"}
          </button>
        </form>
      </div>

      <div style={{ background: '#fff', padding: '20px', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
        <h2>Employee Directory (DynamoDB)</h2>
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: '15px' }}>
          <thead>
            <tr style={{ background: '#f1f1f1', textAlign: 'left' }}>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>ID</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Name</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Email</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Department</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Salary</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {employees.length === 0 ? (
              <tr><td colSpan="6" style={{ textAlign: 'center', padding: '20px', color: '#888' }}>No employees found.</td></tr>
            ) : (
              employees.map(emp => (
                <tr key={emp.id} style={{ borderBottom: '1px solid #ddd' }}>
                  <td style={{ padding: '10px', fontSize: '12px', color: '#555' }}>{emp.id}</td>
                  <td style={{ padding: '10px' }}>{emp.name}</td>
                  <td style={{ padding: '10px' }}>{emp.email}</td>
                  <td style={{ padding: '10px' }}>{emp.department}</td>
                  <td style={{ padding: '10px' }}>${emp.salary.toLocaleString()}</td>
                  <td style={{ padding: '10px' }}>
                    <button onClick={() => handleDelete(emp.id)} style={{ background: '#dc3545', color: '#fff', border: 'none', padding: '6px 12px', borderRadius: '4px', cursor: 'pointer' }}>Delete</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
export default App;
